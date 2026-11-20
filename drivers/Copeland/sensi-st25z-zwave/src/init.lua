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

local capabilities = require "st.capabilities"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.ThermostatFanMode
local ThermostatFanMode = (require "st.zwave.CommandClass.ThermostatFanMode")({version=3})
--- @type st.zwave.CommandClass.ThermostatMode
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({version=2})

local function device_added(driver, device)
  if device:supports_capability_by_id(capabilities.thermostatMode.ID) and
    device:is_cc_supported(cc.THERMOSTAT_MODE) then
    device:send(ThermostatMode:SupportedGet({}))
  end
  if device:supports_capability_by_id(capabilities.thermostatFanMode.ID) and
    device:is_cc_supported(cc.THERMOSTAT_FAN_MODE) then
    device:send(ThermostatFanMode:SupportedGet({}))
  end
  device:refresh()
end

local driver_template = {
  supported_capabilities = {
    capabilities.temperatureAlarm,
    capabilities.temperatureMeasurement,
    capabilities.thermostatHeatingSetpoint,
    capabilities.thermostatCoolingSetpoint,
    capabilities.thermostatOperatingState,
    capabilities.thermostatMode,
    capabilities.thermostatFanMode,
    capabilities.relativeHumidityMeasurement,
    capabilities.battery,
    capabilities.powerMeter,
    capabilities.energyMeter
  },
  lifecycle_handlers = {
    added = device_added
  },
  sub_drivers = require("sub_drivers")
}

defaults.register_for_default_handlers(
  driver_template,
  driver_template.supported_capabilities,
  { native_capability_attrs_enabled = true })
--- @type st.zwave.Driver
local thermostat = ZwaveDriver("zwave_thermostat", driver_template)
thermostat:run()