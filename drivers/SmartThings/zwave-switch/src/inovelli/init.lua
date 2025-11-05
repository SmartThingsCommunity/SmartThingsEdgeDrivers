-- Copyright 2025 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
--- @type st.zwave.CommandClass.Association
local Association = (require "st.zwave.CommandClass.Association")({ version = 1 })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({version=4})
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })
local preferencesMap = require "preferences"

--- @type st.utils
local utils = require "st.utils"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
local log = require "log"
local st_device = require "st.device"

--- @type st.zwave.CommandClass.CentralScene
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({version=3})
--- @type st.zwave.constants
local constants = require "st.zwave.constants"

local LATEST_CLOCK_SET_TIMESTAMP = "latest_clock_set_timestamp"

local GEN3_NOTIFICATION_PARAMETER_NUMBER = 99
local GEN2_NOTIFICATION_PARAMETER_NUMBER = 16
local LED_COLOR_CONTROL_PARAMETER_NUMBER = 13
local LED_BAR_COMPONENT_NAME = "LEDColorConfiguration"
local LED_GENERIC_SATURATION = 100

local INOVELLI_FINGERPRINTS = {
  { mfr = 0x031E, prod = 0x0017, model = 0x0001 }, -- Inovelli VZW32-SN
  { mfr = 0x031E, prod = 0x0001, model = 0x0001 }, -- Inovelli LZW31SN
  { mfr = 0x031E, prod = 0x0003, model = 0x0001 }, -- Inovelli LZW31
}

-- Device type detection helpers
local function is_gen2(device)
  return device:id_match(0x031E, {0x0001, 0x0003}, 0x0001)
end

local function is_gen3(device)
  return device:id_match(0x031E, {0x0015, 0x0017}, 0x0001)
end

-- Helper function to get the correct notification parameter number based on device type
local function get_notification_parameter_number(device)
  -- For child devices, check the parent device type
  local device_to_check = device
  if device.network_type == st_device.NETWORK_TYPE_CHILD then
    device_to_check = device:get_parent_device()
  end

  if is_gen3(device_to_check) then
    return GEN3_NOTIFICATION_PARAMETER_NUMBER
  else
    return GEN2_NOTIFICATION_PARAMETER_NUMBER
  end
end

local function button_to_component(buttonId)
  if buttonId > 0 then
    return string.format("button%d", buttonId)
  end
end

local function huePercentToValue(value)
  if value <= 2 then
    return 0
  elseif value >= 98 then
    return 255
  else
    return utils.round(value / 100 * 255)
  end
end

local function valueToHuePercent(value)
  if value <= 2 then
    return 0
  elseif value >= 254 then
    return 100
  else
    return utils.round(value / 255 * 100)
  end
end

local preferences_to_numeric_value = function(new_value)
  local numeric = tonumber(new_value)
  if numeric == nil then -- in case the value is boolean
    numeric = new_value and 1 or 0
  end
  return numeric
end

local preferences_calculate_parameter = function(new_value, type, number)
  if type == 4 and new_value > 2147483647 then
    return ((4294967296 - new_value) * -1)
  elseif type == 2 and new_value > 32767 then
    return ((65536 - new_value) * -1)
  elseif type == 1 and new_value > 127 then
    return ((256 - new_value) * -1)
  else
    return new_value
  end
end

local function add_child(driver,parent,profile,child_type)
  local child_metadata = {
      type = "EDGE_CHILD",
      label = string.format("%s %s", parent.label, child_type:gsub("(%l)(%w*)", function(a,b) return string.upper(a)..b end)),
      profile = profile,
      parent_device_id = parent.id,
      parent_assigned_child_key = child_type,
      vendor_provided_label = string.format("%s %s", parent.label, child_type:gsub("(%l)(%w*)", function(a,b) return string.upper(a)..b end))
  }
  driver:try_create_device(child_metadata)
end

local function getNotificationValue(device, value)
  local level = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) or 100
  local color = utils.round(device:get_latest_state("main", capabilities.colorControl.ID, capabilities.colorControl.hue.NAME) or 100)
  local effect = device:get_parent_device().preferences.notificationType or 1
  local duration = 255 -- Default duration

  -- Get the parent device to check generation for child devices
  local device_to_check = device
  if device.network_type == st_device.NETWORK_TYPE_CHILD then
    device_to_check = device:get_parent_device()
  end

  local colorValue = huePercentToValue(value or color)
  local notificationValue = 0

  if is_gen3(device_to_check) then
    -- Gen3 order: duration, level, color, effect (bytes 0-3 from low to high)
    notificationValue = notificationValue + (effect * 16777216)   -- byte 3 (highest)
    notificationValue = notificationValue + (colorValue * 65536)   -- byte 2
    notificationValue = notificationValue + (level * 256)          -- byte 1
    notificationValue = notificationValue + (duration * 1)        -- byte 0 (lowest)
  else
    -- Gen2 order: color, level, duration, effect (bytes 0-3 from low to high)
    notificationValue = notificationValue + (effect * 16777216)    -- byte 3 (highest)
    notificationValue = notificationValue + (duration * 65536)     -- byte 2
    notificationValue = notificationValue + (level * 256)          -- byte 1
    notificationValue = notificationValue + (colorValue * 1)        -- byte 0 (lowest)
  end

  return notificationValue
end

local function set_color(driver, device, command)
  if device.network_type == st_device.NETWORK_TYPE_CHILD then
    device:emit_event(capabilities.colorControl.hue(command.args.color.hue))
    device:emit_event(capabilities.colorControl.saturation(command.args.color.saturation))
    device:emit_event(capabilities.switch.switch("on"))
    local dev = device:get_parent_device()
    local config = Configuration:Set({
      parameter_number=get_notification_parameter_number(device),
      configuration_value=getNotificationValue(device),
      size=4
    })
    local send_configuration = function()
      dev:send(config)
    end
    device.thread:call_with_delay(1,send_configuration)
  else
    local value = huePercentToValue(command.args.color.hue)
    local config = Configuration:Set({
      parameter_number=LED_COLOR_CONTROL_PARAMETER_NUMBER,
      configuration_value=value,
      size=2
    })
    device:send(config)

    local query_configuration = function()
      device:send(Configuration:Get({ parameter_number=LED_COLOR_CONTROL_PARAMETER_NUMBER }))
    end

    device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, query_configuration)
  end
end

local function set_color_temperature(driver, device, command)
  if device.network_type == st_device.NETWORK_TYPE_CHILD then
    device:emit_event(capabilities.colorControl.hue(100))
    device:emit_event(capabilities.colorTemperature.colorTemperature(command.args.temperature))
    device:emit_event(capabilities.switch.switch("on"))
    local dev = device:get_parent_device()
    local config = Configuration:Set({
      parameter_number=get_notification_parameter_number(device),
      configuration_value=getNotificationValue(device, 100),
      size=4
    })
    local send_configuration = function()
      dev:send(config)
    end
    device.thread:call_with_delay(1,send_configuration)
  else
    local value = huePercentToValue(100)
    local config = Configuration:Set({
      parameter_number=LED_COLOR_CONTROL_PARAMETER_NUMBER,
      configuration_value=value,
      size=2
    })
    device:send(config)

    local query_configuration = function()
      device:send(Configuration:Get({ parameter_number=LED_COLOR_CONTROL_PARAMETER_NUMBER }))
    end

    device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, query_configuration)
  end
end

local function switch_level_set(driver, device, command)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    local level = utils.round(command.args.level)
    level = utils.clamp_value(level, 0, 99)

    device:send(SwitchMultilevel:Set({ value=level, duration=command.args.rate or "default" }))

    device.thread:call_with_delay(3, function(d)
      device:send(SwitchMultilevel:Get({}))
    end)
  else
    device:emit_event(capabilities.switchLevel.level(command.args.level))
    device:emit_event(capabilities.switch.switch(command.args.level ~= 0 and "on" or "off"))
    local dev = device:get_parent_device()
    local config = Configuration:Set({
      parameter_number=get_notification_parameter_number(device),
      configuration_value=getNotificationValue(device),
      size=4
    })
    local send_configuration = function()
      dev:send(config)
    end
    device.thread:call_with_delay(1,send_configuration)
  end
end

local function refresh_handler(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    device:send(SwitchMultilevel:Get({}))
    device:send(Meter:Get({ scale = Meter.scale.electric_meter.WATTS }))
    device:send(Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }))
  end
end

local function device_added(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    device:send(Association:Set({grouping_identifier = 1, node_ids = {driver.environment_info.hub_zwave_id}}))
    refresh_handler(driver, device)
  else
    device:emit_event(capabilities.colorControl.hue(1))
    device:emit_event(capabilities.colorControl.saturation(1))
    device:emit_event(capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = 2700, maximum = 6500} }))
    device:emit_event(capabilities.switchLevel.level(100))
    device:emit_event(capabilities.switch.switch("off"))
  end
end

local function info_changed(driver, device, event, args)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    local time_diff = 3
    local last_clock_set_time = device:get_field(LATEST_CLOCK_SET_TIMESTAMP)
    if last_clock_set_time ~= nil then
        time_diff = os.difftime(os.time(), last_clock_set_time)
    end
    device:set_field(LATEST_CLOCK_SET_TIMESTAMP, os.time(), {persist = true})
    if time_diff > 2 then
      local preferences = preferencesMap.get_device_parameters(device)
      if args.old_st_store.preferences["notificationChild"] ~= device.preferences.notificationChild and args.old_st_store.preferences["notificationChild"] == false and device.preferences.notificationChild == true then
        if not device:get_child_by_parent_assigned_key('notification') then
          add_child(driver,device,'rgbw-bulb','notification')
        end
      end

      for id, value in pairs(device.preferences) do
        if args.old_st_store.preferences[id] ~= value and preferences and preferences[id] then
          local new_parameter_value = preferences_calculate_parameter(preferences_to_numeric_value(device.preferences[id]), preferences[id].size, id)
          device:send(Configuration:Set({parameter_number = preferences[id].parameter_number, size = preferences[id].size, configuration_value = new_parameter_value}))
        end
      end
    else
      log.info("info_changed running more than once. Cancelling this run. Time diff: " .. time_diff)
    end
  end
end

local function switch_set_on_off_handler(value)
  return function(driver, device, command)

    if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
      device:send(Basic:Set({ value = value }))
      device.thread:call_with_delay(3, function(d)
        device:send(SwitchMultilevel:Get({}))
      end)
    else
      device:emit_event(capabilities.switch.switch(value == 0 and "off" or "on"))
      local dev = device:get_parent_device()
      local config = Configuration:Set({
        parameter_number=get_notification_parameter_number(device),
        configuration_value=(value == 0 and 0 or getNotificationValue(device)),
        size=4
      })
      local send_configuration = function()
        dev:send(config)
      end
      device.thread:call_with_delay(1,send_configuration)
    end
  end
end

local function configuration_report(driver, device, cmd)
  if cmd.args.parameter_number == LED_COLOR_CONTROL_PARAMETER_NUMBER and is_gen2(device) then
    local hue = valueToHuePercent(cmd.args.configuration_value)

    local ledBarComponent = device.profile.components[LED_BAR_COMPONENT_NAME]
    if ledBarComponent ~= nil then
      device:emit_component_event(ledBarComponent, capabilities.colorControl.hue(hue))
      device:emit_component_event(ledBarComponent, capabilities.colorControl.saturation(LED_GENERIC_SATURATION))
    end
  end
end

local map_key_attribute_to_capability = {
  [CentralScene.key_attributes.KEY_PRESSED_1_TIME] = capabilities.button.button.pushed,
  [CentralScene.key_attributes.KEY_RELEASED] = capabilities.button.button.held,
  [CentralScene.key_attributes.KEY_HELD_DOWN] = capabilities.button.button.down_hold,
  [CentralScene.key_attributes.KEY_PRESSED_2_TIMES] = capabilities.button.button.pushed_2x,
  [CentralScene.key_attributes.KEY_PRESSED_3_TIMES] = capabilities.button.button.pushed_3x,
  [CentralScene.key_attributes.KEY_PRESSED_4_TIMES] = capabilities.button.button.pushed_4x,
  [CentralScene.key_attributes.KEY_PRESSED_5_TIMES] = capabilities.button.button.pushed_5x,
}

local function central_scene_notification_handler(self, device, cmd)
  if ( cmd.args.scene_number ~= nil and cmd.args.scene_number ~= 0 ) then
    local button_number = cmd.args.scene_number
    local capability_attribute = map_key_attribute_to_capability[cmd.args.key_attributes]
    local additional_fields = {
      state_change = true
    }

    local event
    if capability_attribute ~= nil then
      event = capability_attribute(additional_fields)
    end

    if event ~= nil then
      -- device reports scene notifications from endpoint 0 (main) but central scene events have to be emitted for button components: 1,2,3
      local comp = device.profile.components[button_to_component(button_number)]
      if comp ~= nil then
        device:emit_component_event(comp, event)
      end
    end
  end
end

local function can_handle_inovelli(opts, driver, device, ...)
  for _, fingerprint in ipairs(INOVELLI_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("inovelli")
      return true, subdriver
    end
  end
  return false
end

-------------------------------------------------------------------------------------------
-- Register message handlers and run driver
-------------------------------------------------------------------------------------------
local inovelli = {
  NAME = "Inovelli Devices",
  lifecycle_handlers = {
    infoChanged = info_changed,
    added = device_added,
  },
  zwave_handlers = {
    [cc.CENTRAL_SCENE] = {
      [CentralScene.NOTIFICATION] = central_scene_notification_handler
    },
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.switch.on.NAME] = switch_set_on_off_handler(SwitchBinary.value.ON_ENABLE),
      [capabilities.switch.switch.off.NAME] = switch_set_on_off_handler(SwitchBinary.value.OFF_DISABLE)
    },
    [capabilities.colorControl.ID] = {
      [capabilities.colorControl.commands.setColor.NAME] = set_color
    },
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = set_color_temperature
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = switch_level_set
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler
    }
  },
  sub_drivers = {
    require("inovelli/vzw32-sn"),
    require("inovelli/lzw31-sn")
  },
  can_handle = can_handle_inovelli
}

return inovelli