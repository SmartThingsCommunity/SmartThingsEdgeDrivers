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

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement

local ZIGBEE_DIMMER_POWER_ENERGY_FINGERPRINTS = {
  { mfr = "Jasco Products", model = "43082" }
}

local is_zigbee_dimmer_power_energy = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_DIMMER_POWER_ENERGY_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("zigbee-dimmer-power-energy")
      return true, subdriver
    end
  end
  return false
end

local do_configure = function(self, device)
  device:refresh()
  device:configure()

  -- Additional one time configuration
  if  device:supports_capability(capabilities.powerMeter) then
    -- Divisor and multipler for PowerMeter
    device:send(SimpleMetering.attributes.Divisor:read(device))
    device:send(SimpleMetering.attributes.Multiplier:read(device))
  end

  if device:supports_capability(capabilities.energyMeter) then
    -- Divisor and multipler for EnergyMeter
    device:send(ElectricalMeasurement.attributes.ACPowerDivisor:read(device))
    device:send(ElectricalMeasurement.attributes.ACPowerMultiplier:read(device))
  end
end

local zigbee_dimmer_power_energy_handler = {
  NAME = "zigbee dimmer power energy handler",
  lifecycle_handlers = {
    doConfigure = do_configure,
  },
  sub_drivers = {
    require("zigbee-dimmer-power-energy/enbrighten-metering-dimmer")
  },
  can_handle = is_zigbee_dimmer_power_energy

}

return zigbee_dimmer_power_energy_handler
