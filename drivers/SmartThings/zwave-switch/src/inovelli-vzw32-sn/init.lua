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
local preferencesMap = require "preferences"

--- @type st.utils
local utils = require "st.utils"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
local log = require "log"
local st_device = require "st.device"

--- @type st.zwave.CommandClass.CentralScene
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({version=3})

local LATEST_CLOCK_SET_TIMESTAMP = "latest_clock_set_timestamp"

local NOTIFICATION_PARAMETER_NUMBER = 99

local INOVELLI_VZW32_SN_FINGERPRINTS = {
  { mfr = 0x031E, prod = 0x0017, model = 0x0001 } -- Inovelli VZW32-SN
}

--- Map component to end_points(channels)
---
--- @param device st.zwave.Device
--- @param component_id string ID
--- @return table dst_channels destination channels e.g. {2} for Z-Wave channel 2 or {} for unencapsulated
local function component_to_endpoint(device, component_id)
  local ep_num = component_id:match("switch(%d)")
  return { ep_num and tonumber(ep_num) }
end

--- Map end_point(channel) to Z-Wave endpoint 9 channel)
---
--- @param device st.zwave.Device
--- @param ep number the endpoint(Z-Wave channel) ID to find the component for
--- @return string the component ID the endpoint matches to
local function endpoint_to_component(device, ep)
  local switch_comp = string.format("switch%d", ep)
  if device.profile.components[switch_comp] ~= nil then
    return switch_comp
  else
    return "main"
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

local function initialize(device)
  if device:get_latest_state("main", capabilities.illuminanceMeasurement.ID, capabilities.illuminanceMeasurement.illuminance.NAME) == nil then
    device:emit_event(capabilities.illuminanceMeasurement.illuminance(0))
  end
  if device:get_latest_state("main", capabilities.motionSensor.ID, capabilities.motionSensor.motion.NAME) == nil then
    device:emit_event(capabilities.motionSensor.motion.active())
  end
  if device:get_latest_state("main", capabilities.powerMeter.ID, capabilities.powerMeter.power.NAME) == nil then
    device:emit_event(capabilities.powerMeter.power(0))
  end
  if device:get_latest_state("main", capabilities.energyMeter.ID, capabilities.energyMeter.energy.NAME) == nil then
    device:emit_event(capabilities.energyMeter.energy(0))
  end
  if device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) == nil then
    device:emit_event(capabilities.switchLevel.level(0))
  end

  for _, component in pairs(device.profile.components) do
    if string.find(component.id, "button") ~= nil then
      if device:get_latest_state(component.id, capabilities.button.ID, capabilities.button.supportedButtonValues.NAME) == nil then
        device:emit_component_event(
          component,
          capabilities.button.supportedButtonValues(
            {"pushed","held","down_hold","pushed_2x","pushed_3x","pushed_4x","pushed_5x"},
            { visibility = { displayed = false } }
          )
        )
        device:emit_component_event(
          component,
          capabilities.button.numberOfButtons({value = 1}, { visibility = { displayed = false } })
        )
      end
    end
  end
end

local function getNotificationValue(device, value)
  local notificationValue = 0
  local level = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) or 100
  local color = utils.round(device:get_latest_state("main", capabilities.colorControl.ID, capabilities.colorControl.hue.NAME) or 100)
  local effect = device:get_parent_device().preferences.notificationType or 1
  notificationValue = notificationValue + (effect*16777216)
  notificationValue = notificationValue + (huePercentToValue(value or color)*65536)
  notificationValue = notificationValue + (level*256)
  notificationValue = notificationValue + (255*1)
  return notificationValue
end

local function set_color(driver, device, command)
  device:emit_event(capabilities.colorControl.hue(command.args.color.hue))
  device:emit_event(capabilities.colorControl.saturation(command.args.color.saturation))
  device:emit_event(capabilities.switch.switch("on"))
  local dev = device:get_parent_device()
  local config = Configuration:Set({
    parameter_number=NOTIFICATION_PARAMETER_NUMBER,
    configuration_value=getNotificationValue(device),
    size=4
  })
  local send_configuration = function()
    dev:send(config)
  end
  device.thread:call_with_delay(1,send_configuration)
end

local function set_color_temperature(driver, device, command)
  device:emit_event(capabilities.colorControl.hue(100))
  device:emit_event(capabilities.colorTemperature.colorTemperature(command.args.temperature))
  device:emit_event(capabilities.switch.switch("on"))
  local dev = device:get_parent_device()
  local config = Configuration:Set({
    parameter_number=NOTIFICATION_PARAMETER_NUMBER,
    configuration_value=getNotificationValue(device, 100),
    size=4
  })
  local send_configuration = function()
    dev:send(config)
  end
  device.thread:call_with_delay(1,send_configuration)
end

local function switch_level_set(driver, device, command)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    local level = utils.round(command.args.level)
    level = utils.clamp_value(level, 0, 99)

    device:emit_event(level > 0 and capabilities.switch.switch.on() or capabilities.switch.switch.off())

    device:send(SwitchMultilevel:Set({ value=level, duration=command.args.rate or "default" }))

    device.thread:call_with_delay(3, function(d)
      device:send(SwitchMultilevel:Get({}))
    end)
  else
    device:emit_event(capabilities.switchLevel.level(command.args.level))
    device:emit_event(capabilities.switch.switch(command.args.level ~= 0 and "on" or "off"))
    local dev = device:get_parent_device()
    local config = Configuration:Set({
      parameter_number=NOTIFICATION_PARAMETER_NUMBER,
      configuration_value=getNotificationValue(device),
      size=4
    })
    local send_configuration = function()
      dev:send(config)
    end
    device.thread:call_with_delay(1,send_configuration)
  end
end

local function can_handle_inovelli_vzw32(opts, driver, device, ...)
  for _, fingerprint in ipairs(INOVELLI_VZW32_SN_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("inovelli-vzw32-sn")
      return true, subdriver
    end
  end
  return false
end

local device_init = function(self, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    device:set_component_to_endpoint_fn(component_to_endpoint)
    device:set_endpoint_to_component_fn(endpoint_to_component)
    initialize(device)
  else
    if device:get_latest_state("main", capabilities.colorControl.ID, capabilities.colorControl.hue.NAME) == nil then
      device:emit_event(capabilities.colorControl.hue(1))
    end
    if device:get_latest_state("main", capabilities.colorControl.ID, capabilities.colorControl.saturation.NAME) == nil then
      device:emit_event(capabilities.colorControl.saturation(1))
    end
    if device:get_latest_state("main", capabilities.colorTemperature.ID, capabilities.colorTemperature.colorTemperature.NAME) == nil then
      device:emit_event(capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = 2700, maximum = 6500} }))
      device:emit_event(capabilities.colorTemperature.colorTemperature(6500))
    end
    if device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) == nil then
      device:emit_event(capabilities.switchLevel.level(100))
    end
    if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == nil then
      device:emit_event(capabilities.switch.switch("off"))
    end
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
          add_child(driver,device,'rgbw-bulb','notificaiton')
        end
      end

      for id, value in pairs(device.preferences) do
        if args.old_st_store.preferences[id] ~= value and preferences and preferences[id] then
          local new_parameter_value = preferences_calculate_parameter(preferences_to_numeric_value(device.preferences[id]), preferences[id].size, id)
          device:send(Configuration:Set({parameter_number = preferences[id].parameter_number, size = preferences[id].size, configuration_value = new_parameter_value}))
        end
      end
      device:send(Association:Set({grouping_identifier = 1, node_ids = {driver.environment_info.hub_zwave_id}}))
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
        parameter_number=NOTIFICATION_PARAMETER_NUMBER,
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

-------------------------------------------------------------------------------------------
-- Register message handlers and run driver
-------------------------------------------------------------------------------------------
local inovelli_vzw32_sn = {
  NAME = "inovelli vzw32-sn handler",
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed,
  },
  zwave_handlers = {
    [cc.CENTRAL_SCENE] = {
      [CentralScene.NOTIFICATION] = central_scene_notification_handler
    },
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
    }
  },
  can_handle = can_handle_inovelli_vzw32
}

return inovelli_vzw32_sn