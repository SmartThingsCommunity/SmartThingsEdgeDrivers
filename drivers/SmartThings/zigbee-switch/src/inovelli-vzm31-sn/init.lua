-- Copyright 2024 SmartThings
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

local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local utils = require "st.utils"
local st_device = require "st.device"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local device_management = require "st.zigbee.device_management"

local LATEST_CLOCK_SET_TIMESTAMP = "latest_clock_set_timestamp"

local INOVELLI_VZM31_SN_FINGERPRINTS = {
  { mfr = "Inovelli", model = "VZM31-SN" }
}

local PRIVATE_CLUSTER_ID = 0xFC31
local PRIVATE_CMD_NOTIF_ID = 0x01
local PRIVATE_CMD_SCENE_ID =0x00
local MFG_CODE = 0x122F

local preference_map = {
      parameter258 = {parameter_number = 258, size = data_types.Boolean},
      parameter22 = {parameter_number = 22, size = data_types.Uint8},
      parameter52 = {parameter_number = 52, size = data_types.Boolean},
      parameter1 = {parameter_number = 1, size = data_types.Uint8},
      parameter2 = {parameter_number = 2, size = data_types.Uint8},
      parameter3 = {parameter_number = 3, size = data_types.Uint8},
      parameter4 = {parameter_number = 4, size = data_types.Uint8},
      parameter9 = {parameter_number = 9, size = data_types.Uint8},
      parameter10 = {parameter_number = 10, size = data_types.Uint8},
      parameter11 = {parameter_number = 11, size = data_types.Boolean},
      parameter15 = {parameter_number = 15, size = data_types.Uint8},
      parameter17 = {parameter_number = 17, size = data_types.Uint8},
      parameter95 = {parameter_number = 95, size = data_types.Uint8},
      parameter96 = {parameter_number = 96, size = data_types.Uint8},
      parameter97 = {parameter_number = 97, size = data_types.Uint8},
      parameter98 = {parameter_number = 98, size = data_types.Uint8},
}

local preferences_to_numeric_value = function(new_value)
  local numeric = tonumber(new_value)
  if numeric == nil then -- in case the value is Boolean
    numeric = new_value and 1 or 0
  end
  return numeric
end

local preferences_calculate_parameter = function(new_value, type, number)
  if number == "parameter9" or number == "parameter10" or number == "parameter13" or number == "parameter14"  or number == "parameter15" or number == "parameter55" or number == "parameter56" then
    if new_value == 101 then
      return 255
    else
      return utils.round(new_value / 100 * 254)
    end
  else
    return new_value
  end
end

local is_inovelli_vzm31_sn = function(opts, driver, device)
  for _, fingerprint in ipairs(INOVELLI_VZM31_SN_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("inovelli-vzm31-sn")
      return true, subdriver
    end
  end
  return false
end

local function to_boolean(value)
  if value == 0 or value =="0" then
    return false
  else
    return true
  end
end

local map_key_attribute_to_capability = {
  [0x00] = capabilities.button.button.pushed,
  [0x01] = capabilities.button.button.held,
  [0x02] = capabilities.button.button.down_hold,
  [0x03] = capabilities.button.button.pushed_2x,
  [0x04] = capabilities.button.button.pushed_3x,
  [0x05] = capabilities.button.button.pushed_4x,
  [0x06] = capabilities.button.button.pushed_5x,
}

local function button_to_component(buttonId)
  if buttonId > 0 then
    return string.format("button%d", buttonId)
  end
end

local function scene_handler(driver, device, zb_rx)
  local bytes = zb_rx.body.zcl_body.body_bytes
  local button_number = bytes:byte(1)
  local capability_attribute = map_key_attribute_to_capability[bytes:byte(2)]
  local additional_fields = {
    state_change = true
  }

  local event
  if capability_attribute ~= nil then
    event = capability_attribute(additional_fields)
  end

  local comp = device.profile.components[button_to_component(button_number)]
  if comp ~= nil then
    device:emit_component_event(comp, event)
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

local function info_changed(driver, device, event, args)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    local time_diff = 3
    local last_clock_set_time = device:get_field(LATEST_CLOCK_SET_TIMESTAMP)
    if last_clock_set_time ~= nil then
        time_diff = os.difftime(os.time(), last_clock_set_time)
    end
    device:set_field(LATEST_CLOCK_SET_TIMESTAMP, os.time(), {persist = true})

    if time_diff > 2 then
      local preferences = preference_map
      if args.old_st_store.preferences["notificationChild"] ~= device.preferences.notificationChild and args.old_st_store.preferences["notificationChild"] == false and device.preferences.notificationChild == true then
        if not device:get_child_by_parent_assigned_key('notification') then
          add_child(driver,device,'rgbw-bulb-2700K-6500K','notificaiton')
        end
      end
      for id, value in pairs(device.preferences) do
        if args.old_st_store.preferences[id] ~= value and preferences and preferences[id] then
          local new_parameter_value = preferences_calculate_parameter(preferences_to_numeric_value(device.preferences[id]), preferences[id].size, id)

          if(preferences[id].size == data_types.Boolean) then
            device:send(cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, preferences[id].parameter_number, MFG_CODE, preferences[id].size, to_boolean(new_parameter_value)))
          else
            device:send(cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, preferences[id].parameter_number, MFG_CODE, preferences[id].size, new_parameter_value))
          end
        end
      end
      device:send(cluster_base.read_attribute(device, data_types.ClusterId(0x0000), 0x4000))
    end
  end
end

local do_configure = function(self, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    device:refresh()
    device:configure()

    device:send(device_management.build_bind_request(device, PRIVATE_CLUSTER_ID, self.environment_info.hub_zigbee_eui, 2)) -- Bind device for button presses.

    -- Retrieve Neutral Setting "Parameter 21"
    device:send(cluster_base.read_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, 21, MFG_CODE))
    device:send(cluster_base.read_attribute(device, data_types.ClusterId(0x0000), 0x4000))

    -- Additional one time configuration
    if  device:supports_capability(capabilities.powerMeter) then
      -- Divisor and multipler for PowerMeter
      device:send(clusters.SimpleMetering.attributes.Divisor:read(device))
      device:send(clusters.SimpleMetering.attributes.Multiplier:read(device))
    end

    if device:supports_capability(capabilities.energyMeter) then
      -- Divisor and multipler for EnergyMeter
      device:send(clusters.ElectricalMeasurement.attributes.ACPowerDivisor:read(device))
      device:send(clusters.ElectricalMeasurement.attributes.ACPowerMultiplier:read(device))
    end
  end
end

local device_init = function(self, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    device:set_field(LATEST_CLOCK_SET_TIMESTAMP, os.time())
    if device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) == nil and device:supports_capability(capabilities.switchLevel)then
      device:emit_event(capabilities.switchLevel.level(0))
    end
    if device:get_latest_state("main", capabilities.powerMeter.ID, capabilities.powerMeter.power.NAME) == nil and device:supports_capability(capabilities.powerMeter) then
      device:emit_event(capabilities.powerMeter.power(0))
    end
    if device:get_latest_state("main", capabilities.energyMeter.ID, capabilities.energyMeter.energy.NAME) == nil and device:supports_capability(capabilities.energyMeter)then
      device:emit_event(capabilities.energyMeter.energy(0))
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
        end
        if device:get_latest_state(component.id, capabilities.button.ID, capabilities.button.numberOfButtons.NAME) == nil then
          device:emit_component_event(
            component,
            capabilities.button.numberOfButtons({value = 1}, { visibility = { displayed = false } })
          )
        end
      end
    end
    device:send(cluster_base.read_attribute(device, data_types.ClusterId(0x0000), 0x4000))
  else
    device:emit_event(capabilities.colorControl.hue(1))
    device:emit_event(capabilities.colorControl.saturation(1))
    device:emit_event(capabilities.colorTemperature.colorTemperature(6500))
    device:emit_event(capabilities.switchLevel.level(100))
    device:emit_event(capabilities.switch.switch("off"))
  end
end

local function energy_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  raw_value = raw_value / 100
  device:emit_event(capabilities.energyMeter.energy({value = raw_value, unit = "kWh" }))
end

local function power_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  raw_value = raw_value / 10
  device:emit_event(capabilities.powerMeter.power({value = raw_value, unit = "W" }))
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

local function on_handler(driver, device, command)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    device:send(clusters.OnOff.server.commands.On(device))
  else
    device:emit_event(capabilities.switch.switch("on"))
    local dev = device:get_parent_device()
    local send_configuration = function()
      dev:send(cluster_base.build_manufacturer_specific_command(
            dev,
            PRIVATE_CLUSTER_ID,
            PRIVATE_CMD_NOTIF_ID,
            MFG_CODE,
            utils.serialize_int(getNotificationValue(device),4,false,false)))
    end
    device.thread:call_with_delay(1,send_configuration)
  end
end

local function off_handler(driver, device, command)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    device:send(clusters.OnOff.server.commands.Off(device))
  else
    device:emit_event(capabilities.switch.switch("off"))
    local dev = device:get_parent_device()
    local send_configuration = function()
      dev:send(cluster_base.build_manufacturer_specific_command(
            dev,
            PRIVATE_CLUSTER_ID,
            PRIVATE_CMD_NOTIF_ID,
            MFG_CODE,
            utils.serialize_int(0,4,false,false)))
    end
    device.thread:call_with_delay(1,send_configuration)
  end
end

local function switch_level_handler(driver, device, command)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    device:send(clusters.Level.server.commands.MoveToLevelWithOnOff(device, math.floor(command.args.level/100.0 * 254), command.args.rate or 0xFFFF))
  else
    device:emit_event(capabilities.switchLevel.level(command.args.level))
    device:emit_event(capabilities.switch.switch(command.args.level ~= 0 and "on" or "off"))
    local dev = device:get_parent_device()
    local send_configuration = function()
      dev:send(cluster_base.build_manufacturer_specific_command(
            dev,
            PRIVATE_CLUSTER_ID,
            PRIVATE_CMD_NOTIF_ID,
            MFG_CODE,
            utils.serialize_int(getNotificationValue(device),4,false,false)))
    end
    device.thread:call_with_delay(1,send_configuration)
  end
end

local function set_color_temperature(driver, device, command)
  device:emit_event(capabilities.colorControl.hue(100))
  device:emit_event(capabilities.colorTemperature.colorTemperature(command.args.temperature))
  local dev = device:get_parent_device()
  local send_configuration = function()
    dev:send(cluster_base.build_manufacturer_specific_command(
          dev,
          PRIVATE_CLUSTER_ID,
          PRIVATE_CMD_NOTIF_ID,
          MFG_CODE,
          utils.serialize_int(getNotificationValue(device, 100),4,false,false)))
  end
  device.thread:call_with_delay(1,send_configuration)
end

local function set_color(driver, device, command)
  device:emit_event(capabilities.colorControl.hue(command.args.color.hue))
  device:emit_event(capabilities.colorControl.saturation(command.args.color.saturation))
  local dev = device:get_parent_device()
  local send_configuration = function()
    dev:send(cluster_base.build_manufacturer_specific_command(
          dev,
          PRIVATE_CLUSTER_ID,
          PRIVATE_CMD_NOTIF_ID,
          MFG_CODE,
          utils.serialize_int(getNotificationValue(device),4,false,false)))
  end
  device.thread:call_with_delay(1,send_configuration)
end

local inovelli_vzm31_sn = {
  NAME = "inovelli vzm31-sn handler",
  lifecycle_handlers = {
    doConfigure = do_configure,
    init = device_init,
    infoChanged = info_changed
  },
  zigbee_handlers = {
    attr = {
      [clusters.SimpleMetering.ID] = {
        [clusters.SimpleMetering.attributes.InstantaneousDemand.ID] = power_meter_handler,
        [clusters.SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      },
      [clusters.ElectricalMeasurement.ID] = {
        [clusters.ElectricalMeasurement.attributes.ActivePower.ID] = power_meter_handler
      }
    },
    cluster = {
      [PRIVATE_CLUSTER_ID] = {
        [PRIVATE_CMD_SCENE_ID] = scene_handler,
      }
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = on_handler,
      [capabilities.switch.commands.off.NAME] = off_handler,
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = switch_level_handler
    },
    [capabilities.colorControl.ID] = {
      [capabilities.colorControl.commands.setColor.NAME] = set_color
    },
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = set_color_temperature
    }
  },
  can_handle = is_inovelli_vzm31_sn
}

return inovelli_vzm31_sn
