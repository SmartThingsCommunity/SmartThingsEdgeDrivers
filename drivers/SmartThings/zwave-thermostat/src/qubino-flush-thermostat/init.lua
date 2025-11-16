-- Copyright 2022 SmartThings
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

--- @type st.zwave.defaults.switch
local TemperatureMeasurementDefaults = require "st.zwave.defaults.temperatureMeasurement"

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = (require "st.zwave.CommandClass")
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=1 })
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({version=3})
--- @type st.zwave.CommandClass.ThermostatSetpoint
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({ version = 1 })
--- @type st.zwave.CommandClass.ThermostatMode
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({ version = 2 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 2 })
--- @type st.zwave.CommandClass.ThermostatOperatingState
local ThermostatOperatingState = (require "st.zwave.CommandClass.ThermostatOperatingState")({version=1})

local QUBINO_FINGERPRINTS = {
  {mfr = 0x0159, prod = 0x0005, model = 0x0054},  -- Qubino Flush On/Off Thermostat 2
}

-- parameter which tells whether device is configured heat or cool thermostat mode
local DEVICE_MODE_PARAMETER = 59
-- thermostat reports -999.9 if the digital temperature sensor is not connected
local DIGITAL_TEMPERATURE_SENSOR_NOT_CONNECTED = -999.9

-- fieldnames
local CONFIGURED_MODE = "configured_mode"

-- field values
local COOL_MODE = "cool"
local HEAT_MODE = "heat"

local function can_handle_qubino_thermostat(opts, driver, device, ...)
  for _, fingerprint in ipairs(QUBINO_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function info_changed(self, device, event, args)
  local new_parameter_value
  local parameter_number
  local size = 1

  if args.old_st_store.preferences.thermostatMode ~= device.preferences.thermostatMode then
    new_parameter_value = device.preferences.thermostatMode
    parameter_number = DEVICE_MODE_PARAMETER
  end

  if new_parameter_value ~= nil and parameter_number ~= nil then
    device:send(Configuration:Set({parameter_number = parameter_number, size = size, configuration_value = new_parameter_value}))
    device:send(Configuration:Get({parameter_number = parameter_number}))
  end
end

local function do_refresh(self, device)
  local current_setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1 -- this is default mode
  if device:get_field(CONFIGURED_MODE) == COOL_MODE then
    current_setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1
  end

  device:send(ThermostatMode:Get({}))
  device:send(SensorMultilevel:Get({}))
  device:send(ThermostatOperatingState:Get({}))
  device:send(ThermostatSetpoint:Get({setpoint_type = current_setpoint_type}))
  device:send(Meter:Get({scale = Meter.scale.electric_meter.WATTS}))
  device:send(Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}))
end

local function configuration_report(driver, device, cmd)
  local parameter_number = cmd.args.parameter_number
  local configuration_value = cmd.args.configuration_value

  if (parameter_number == DEVICE_MODE_PARAMETER and not device:get_field(CONFIGURED_MODE)) then
    local supported_modes = { capabilities.thermostatMode.thermostatMode.off.NAME }
    if configuration_value == 1 then
      device:set_field(CONFIGURED_MODE, COOL_MODE, {persist = true})
      table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.cool.NAME)
      device:try_update_metadata({profile = "qubino-flush-thermostat-cooling"})
    elseif configuration_value == 0 then
      device:set_field(CONFIGURED_MODE, HEAT_MODE, {persist = true})
      table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.heat.NAME)
      device:try_update_metadata({profile = "qubino-flush-thermostat"})
    end
    device:emit_event(capabilities.thermostatMode.supportedThermostatModes(supported_modes, { visibility = { displayed = false } }))
  end
  device:refresh()
end

local function sensor_multilevel_report_handler(driver, device, cmd)
  if (cmd.args.sensor_type == SensorMultilevel.sensor_type.TEMPERATURE and
      cmd.args.sensor_value ~= DIGITAL_TEMPERATURE_SENSOR_NOT_CONNECTED) then
    TemperatureMeasurementDefaults.zwave_handlers[cc.SENSOR_MULTILEVEL][SensorMultilevel.REPORT](driver, device, cmd)
  end
end

local device_added = function (self, device)
  device:set_field(CONFIGURED_MODE, nil, {persist = true})
  device:send(Configuration:Get({parameter_number = DEVICE_MODE_PARAMETER}))
end

local qubino_thermostat = {
  zwave_handlers = {
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report
    },
    [cc.SENSOR_MULTILEVEL] = {
      [SensorMultilevel.REPORT] = sensor_multilevel_report_handler
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    added = device_added,
    infoChanged = info_changed
  },
  NAME = "qubino thermostat",
  can_handle = can_handle_qubino_thermostat
}

return qubino_thermostat
