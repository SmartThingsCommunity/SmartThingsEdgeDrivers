-- Copyright 2021 SmartThings
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
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local zigbee_constants = require "st.zigbee.constants"
local clusters = require "st.zigbee.zcl.clusters"
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering

local do_configure = function(self, device)
  device:refresh()
  device:configure()

  -- Additional one time configuration
  if device:supports_capability(capabilities.energyMeter) or device:supports_capability(capabilities.powerMeter) then
    -- Divisor and multipler for EnergyMeter
    device:send(ElectricalMeasurement.attributes.ACPowerDivisor:read(device))
    device:send(ElectricalMeasurement.attributes.ACPowerMultiplier:read(device))
    -- Divisor and multipler for PowerMeter
    device:send(SimpleMetering.attributes.Divisor:read(device))
    device:send(SimpleMetering.attributes.Multiplier:read(device))
  end
end

local device_init = function(self, device)
  device:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, 1000, {persist = true})
  device:set_field(zigbee_constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 10, {persist = true})
end

local zigbee_power_meter_driver_template = {
  supported_capabilities = {
    capabilities.refresh,
    capabilities.powerMeter,
    capabilities.energyMeter
  },
  sub_drivers = {},
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
  }
}

defaults.register_for_default_handlers(zigbee_power_meter_driver_template, zigbee_power_meter_driver_template.supported_capabilities)
local zigbee_power_meter = ZigbeeDriver("zigbee_power_meter", zigbee_power_meter_driver_template)
zigbee_power_meter:run()
