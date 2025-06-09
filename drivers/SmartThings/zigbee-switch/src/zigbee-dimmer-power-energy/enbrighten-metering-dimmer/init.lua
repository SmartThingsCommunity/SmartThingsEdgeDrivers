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
local constants = require "st.zigbee.constants"
local SimpleMetering = clusters.SimpleMetering
local configurations = require "configurations"

local ENBRIGHTEN_METERING_DIMMER_FINGERPRINTS = {
  { mfr = "Jasco Products", model = "43082" }
}

local is_enbrighten_metering_dimmer = function(opts, driver, device)
  for _, fingerprint in ipairs(ENBRIGHTEN_METERING_DIMMER_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local device_init = function(self, device)
  local customEnergyDivisor = 10000
  device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, customEnergyDivisor, {persist = true})
end

local do_configure = function(self, device)
  device:refresh()
  device:configure()
end

local instantaneous_demand_handler = function(driver, device, value, zb_rx)
  local raw_value = value.value
  local divisor = 10
  raw_value = raw_value / divisor
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.powerMeter.power({value = raw_value, unit = "W" }))
end

local enbrighten_metering_dimmer = {
  NAME = "enbrighten metering dimmer",
  zigbee_handlers = {
    attr = {
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.InstantaneousDemand.ID] = instantaneous_demand_handler
      }
    }
  },
  lifecycle_handlers = {
    init = configurations.power_reconfig_wrapper(device_init),
    doConfigure = do_configure
  },
  can_handle = is_enbrighten_metering_dimmer
}

return enbrighten_metering_dimmer
