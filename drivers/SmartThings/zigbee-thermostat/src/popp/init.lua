-- Copyright 2023 SmartThings
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
-- Zigbee driver utilities
local device_management = require "st.zigbee.device_management"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local data_types = require "st.zigbee.data_types"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local capabilities = require "st.capabilities"
local utils = require "st.utils"
local log = require "log"

-- Zigbee specific cluster
local ThermostatUIConfig = clusters.ThermostatUserInterfaceConfiguration
local PowerConfiguration = clusters.PowerConfiguration
local Thermostat = clusters.Thermostat

-- Capabilities

local TemperatureMeasurement = capabilities.temperatureMeasurement
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint
local ThermostatMode = capabilities.thermostatMode
local TemperatureAlarm = capabilities.temperatureAlarm
local Switch = capabilities.switch

local POPP_THERMOSTAT_FINGERPRINTS = { {
  mfr = "D5X84YU",
  model = "eT093WRO"
}, {
  mfr = "D5X84YU",
  model = "eT093WRG"
} }

local STORED_HEAT_MODE = "stored_heat_mode"

local MFG_CODE = 0x1246
local THERMOSTAT_SETPOINT_CMD_ID = 0x40
local WINDOW_OPEN_DETECTION_ATTR_ID = 0x4000
local EXTERNAL_OPEN_WINDOW_DETECTION_ATTR_ID = 0x4003
local WINDOW_OPEN_DETECTION_MAP = {
  [0x00] = "cleared", -- // "quarantine" default
  [0x01] = "cleared", -- // "closed" window is closed
  [0x02] = "freeze",  -- // "hold" window might be opened
  [0x03] = "freeze",  -- // "opened" window is opened
  [0x04] = "freeze"   -- // "opened_alarm" a closed window was opened externally (=alert)
}

local cluster_configurations = { {
  cluster = Thermostat.ID,
  attribute = WINDOW_OPEN_DETECTION_ATTR_ID,
  minimum_interval = 60,
  maximum_interval = 43200,
  reportable_change = 0,
  data_type = data_types.Enum8,
  mfg_code = MFG_CODE
}, {
  cluster = Thermostat.ID,
  attribute = EXTERNAL_OPEN_WINDOW_DETECTION_ATTR_ID,
  minimum_interval = 0,
  maximum_interval = 65534,
  reportable_change = 0,
  data_type = data_types.Boolean,
  mfg_code = MFG_CODE
} }

-- Preference variables
local KEYPAD_LOCK = "keypadLock"
local VIEWING_DIRECTION = "viewingDirection"
local REGUALTION_SETPOINT_OFFSET = "regulationSetPointOffset"
local VIEWING_DIRECTION_ATTR = 0x4000
local ETRV_ORIENTATION_ATTR = 0x4014
local REGULATION_SETPOINT_OFFSET_ATTR = 0x404B
local WINDOW_OPEN_FEATURE_ATTR = 0x4051

-- preference table
local PREFERENCE_TABLES = {
  keypadLock = {
    clusterId = ThermostatUIConfig.ID,
    attributeId = ThermostatUIConfig.attributes.KeypadLockout.ID,
    dataType = data_types.Enum8
  },
  viewingDirection = {
    clusterId = ThermostatUIConfig.ID,
    attributeId = VIEWING_DIRECTION_ATTR,
    dataType = data_types.Enum8
  },
  eTRVOrientation = {
    clusterId = Thermostat.ID,
    attributeId = ETRV_ORIENTATION_ATTR,
    dataType = data_types.Boolean
  },
  regulationSetPointOffset = {
    clusterId = Thermostat.ID,
    attributeId = REGULATION_SETPOINT_OFFSET_ATTR,
    dataType = data_types.Int8
  },
  windowOpenFeature = {
    clusterId = Thermostat.ID,
    attributeId = WINDOW_OPEN_FEATURE_ATTR,
    dataType = data_types.Boolean
  }
}

local SUPPORTED_MODES = { ThermostatMode.thermostatMode.heat.NAME, ThermostatMode.thermostatMode.eco.NAME }

local is_popp_thermostat = function(opts, driver, device)
  for _, fingerprint in ipairs(POPP_THERMOSTAT_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

-- Helpers

-- has member check function
local has_member = function(haystack, needle)
  for _, value in ipairs(haystack) do
    if (value == needle) then
      return true
    end
  end
  return false
end

-- Handlers

-- Internal window open detection handler
local window_open_detection_handler = function(driver, device, value, zb_rx)
  device:emit_event(TemperatureAlarm.temperatureAlarm(WINDOW_OPEN_DETECTION_MAP[value.value]))
end

-- Switch handler
local switch_handler_factory = function(switch_state)
  return function(driver, device, cmd)
    local get_cmd = switch_state or cmd.command
    local external_window_open

    if get_cmd == 'on' then
      external_window_open = false
    elseif get_cmd == 'off' then
      external_window_open = true
    end

    device:send(cluster_base.write_manufacturer_specific_attribute(device, Thermostat.ID,
      EXTERNAL_OPEN_WINDOW_DETECTION_ATTR_ID, MFG_CODE, data_types.Boolean, external_window_open))
  end
end

-- Turn switch 'on' if its state is 'off'
local turn_switch_on = function(driver, device)
  -- turn thermostat ventile on
  if device:get_latest_state("main", Switch.ID, Switch.switch.NAME) == "off" then
    switch_handler_factory('on')(driver, device)
  end
end

-- custom thermostatMode_handler
local thermostat_mode_handler = function(driver, device, cmd)
  local payload
  local mode = cmd.args.mode

  if has_member(SUPPORTED_MODES, mode) then
    local last_setpointTemp = device:get_latest_state("main", ThermostatHeatingSetpoint.ID,
      ThermostatHeatingSetpoint.heatingSetpoint.NAME) or 21

    -- prepare setpoint for correct 4 char dec format
    last_setpointTemp = math.floor(last_setpointTemp * 100)

    -- convert setpoint value into bytes e.g. 25.5 -> 2550 -> \x09\xF6 -> \xF6\x09
    local p2 = last_setpointTemp & 0xFF
    local p3 = last_setpointTemp >> 8
    local type = 0x00 -- eco

    if mode == ThermostatMode.thermostatMode.heat.NAME then
      -- Setpoint type "1": the actuator will make a large movement to minimize reaction time to UI
      type = 0x01
    elseif mode == ThermostatMode.thermostatMode.eco.NAME then
      -- Setpoint type "0": the behavior will be the same as setting the attribute "Occupied Heating Setpoint" to the same value
      type = 0x00
    end

    -- send thermostat setpoint command
    payload = string.char(type, p2, p3)
    device:send(cluster_base.build_manufacturer_specific_command(device, Thermostat.ID, THERMOSTAT_SETPOINT_CMD_ID,
      MFG_CODE, payload))

    -- turn thermostat ventile on
    turn_switch_on(driver, device)

    device:set_field(STORED_HEAT_MODE, mode)
    device:emit_event(ThermostatMode.thermostatMode[mode]())
  else
    -- Generate event for the mobile client if it is calling us
    device:emit_event(ThermostatMode.thermostatMode(device:get_latest_state("main", ThermostatMode.ID,
      ThermostatMode.thermostatMode.NAME)))
  end
end

-- temperature setpoint handler
local thermostat_setpoint_handler = function(driver, device, command)
  local value = command.args.setpoint
  local type = 0x00 -- default eco

  local mode = device:get_latest_state("main", ThermostatMode.ID, ThermostatMode.thermostatMode.NAME, 'eco')

  if mode == ThermostatMode.thermostatMode.heat.NAME then
    -- Setpoint type "1": the actuator will make a large movement to minimize reaction time to UI
    type = 0x01
  elseif mode == ThermostatMode.thermostatMode.eco.NAME then
    -- Setpoint type "0": the behavior will be the same as setting the attribute "Occupied Heating Setpoint" to the same value
    type = 0x00
  end

  -- prepare setpoint for correct 4 char dec format
  local setpointTemp = math.floor(value * 100)

  -- convert setpoint value into bytes e.g. 25.5 -> 2550 -> \x09\xF6 -> \xF6\x09
  local p2 = setpointTemp & 0xFF
  local p3 = setpointTemp >> 8

  -- send thermostat setpoint command
  local payload = string.char(type, p2, p3)
  device:send(cluster_base.build_manufacturer_specific_command(device, Thermostat.ID, THERMOSTAT_SETPOINT_CMD_ID,
    MFG_CODE, payload))

  -- turn thermostat ventile on
  turn_switch_on(driver, device)

  -- read setpoint
  device.thread:call_with_delay(2, function(d)
    device:send(Thermostat.attributes.OccupiedHeatingSetpoint:read(device))
  end)
end

-- handle temperature
local thermostat_local_temp_attr_handler = function(driver, device, value, zb_rx)
  local temperature = value.value
  -- fetch invalid temperature
  if (temperature == 0x8000 or temperature == -32768) then
    -- use last temperature instead
    temperature = device:get_latest_state("main", TemperatureMeasurement.ID, TemperatureMeasurement.temperature.NAME)
    if (temperature == nil) then
      log.error("Sensor Temperature: INVALID VALUE")
      return
    end
    -- Handle negative C (< 32F) readings
  elseif (temperature > 0x8000) then
    temperature = -(utils.round(2 * (65536 - temperature)) / 2)
  else
    temperature = temperature / 100
  end

  device:emit_event(TemperatureMeasurement.temperature({
    value = temperature,
    unit = "C"
  }))
end

-- handle heating setpoint
local thermostat_heating_set_point_attr_handler = function(driver, device, value, zb_rx)
  local point_value = value.value
  device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({
    value = point_value / 100,
    unit = "C"
  }))

  -- turn thermostat ventile on
  turn_switch_on(driver, device)
end

-- handle external window open detection
local external_open_window_detection_handler = function(driver, device, value, zb_rx)
  local last_switch_state = device:get_latest_state("main", Switch.ID, Switch.switch.NAME)
  local bool_state = nil

  if last_switch_state == 'on' then
    bool_state = false
  elseif last_switch_state == 'off' then
    bool_state = true
  end

  if bool_state ~= value.value then
    if value.value == false then
      device:emit_event(Switch.switch.on())
    else
      device:emit_event(Switch.switch.off())
    end
  end
end

-- Attribute Refresh Function
local do_refresh = function(driver, device)
  local attributes = { Thermostat.attributes.OccupiedHeatingSetpoint, Thermostat.attributes.LocalTemperature,
    ThermostatUIConfig.attributes.KeypadLockout, PowerConfiguration.attributes.BatteryVoltage }
  for _, attribute in pairs(attributes) do
    device:send(attribute:read(device))
  end

  -- refresh custom attributes:
  -- window open state
  -- external window open state
  local custom_thermostat_attributes = { VIEWING_DIRECTION_ATTR, EXTERNAL_OPEN_WINDOW_DETECTION_ATTR_ID }
  for _, attribute in pairs(custom_thermostat_attributes) do
    device:send(cluster_base.read_manufacturer_specific_attribute(device, Thermostat.ID, attribute, MFG_CODE))
  end
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(2.4, 3.2)(driver, device)

  device.thread:call_with_delay(2, function(d)
    -- Add the manufacturer-specific attributes to generate their configure reporting and bind requests
    for _, config in pairs(cluster_configurations) do
      device:add_configured_attribute(config)
      device:add_monitored_attribute(config)
    end
    -- initial set of heating mode
    local stored_heat_mode = device:get_field(STORED_HEAT_MODE) or 'eco'
    local stored_switch_state = device:get_latest_state("main", Switch.ID, Switch.switch.NAME) or 'on'

    -- Set mode
    device:emit_event(ThermostatMode.thermostatMode[stored_heat_mode]())

    -- Set switch state
    device:emit_event(Switch.switch[stored_switch_state]())

    do_refresh(driver, device)
  end)
end

-- Device Added Function
local device_added = function(driver, device)
  -- Set supported thermostat modes
  device:emit_event(ThermostatMode.supportedThermostatModes(SUPPORTED_MODES, {
    visibility = {
      displayed = false
    }
  }))
end

-- Configuration Function
local do_configure = function(driver, device)
  device:configure()

  device:send(device_management.build_bind_request(device, Thermostat.ID, driver.environment_info.hub_zigbee_eui))
  device:send(Thermostat.attributes.LocalTemperature:configure_reporting(device, 5, 300, 10)) -- report temperature changes over 0.1°C
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(device, 5, 300, 50))
end

-- Device Information Changed Function
local function info_changed(driver, device, event, args)
  for name, info in pairs(PREFERENCE_TABLES) do
    -- add namespace to name reference
    if (device.preferences[name] ~= nil and args.old_st_store.preferences[name] ~= device.preferences[name]) then
      local input = device.preferences[name]

      if (name == KEYPAD_LOCK or name == VIEWING_DIRECTION) then
        input = tonumber(input);
      elseif (name == REGUALTION_SETPOINT_OFFSET) then
        input = tonumber(input) * 10 -- prepare to 4 char dec
      end

      -- set keypad lock (child lock)
      if (name == KEYPAD_LOCK) then
        device:send(cluster_base.write_attribute(device, data_types.ClusterId(info.clusterId),
          data_types.AttributeId(info.attributeId),
          data_types.validate_or_build_type(input, info.dataType, "payload")))
      else
        -- set viewing direction (0° or 180°)
        -- set orientation (vertical true/false)
        -- set regulation setpoint offset (-2.5 to 2.5)
        -- enable window open state detection feature (true/false)
        device:send(cluster_base.write_manufacturer_specific_attribute(device, info.clusterId, info.attributeId,
          MFG_CODE, info.dataType, input))
      end
    end
  end
end

local popp_thermostat = {
  NAME = "POPP Smart Thermostat (Zigbee)",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [ThermostatHeatingSetpoint.ID] = {
      [ThermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = thermostat_setpoint_handler
    },
    [ThermostatMode.ID] = {
      [ThermostatMode.commands.setThermostatMode.NAME] = thermostat_mode_handler
    },
    [Switch.ID] = {
      [Switch.commands.on.NAME] = switch_handler_factory('on'),
      [Switch.commands.off.NAME] = switch_handler_factory('off')
    }
  },
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_defaults.battery_volt_attr_handler
      },
      [Thermostat.ID] = {
        [Thermostat.attributes.LocalTemperature.ID] = thermostat_local_temp_attr_handler,
        [Thermostat.attributes.OccupiedHeatingSetpoint.ID] = thermostat_heating_set_point_attr_handler,
        [WINDOW_OPEN_DETECTION_ATTR_ID] = window_open_detection_handler,
        [EXTERNAL_OPEN_WINDOW_DETECTION_ATTR_ID] = external_open_window_detection_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    infoChanged = info_changed
  },
  can_handle = is_popp_thermostat
}

return popp_thermostat
