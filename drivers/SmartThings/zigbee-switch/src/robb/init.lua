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

local constants = require "st.zigbee.constants"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local SimpleMetering = zcl_clusters.SimpleMetering

local ROBB_DIMMER_FINGERPRINTS = {
  { mfr = "ROBB smarrt", model = "ROB_200-011-0" },
  { mfr = "ROBB smarrt", model = "ROB_200-014-0" }
}

local function is_robb_dimmer(opts, driver, device)
  for _, fingerprint in ipairs(ROBB_DIMMER_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("robb")
      return true, subdriver
    end
  end
  return false
end

local do_init = function(driver, device)
  device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1000000, {persist = true})
  device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 10, {persist = true})
end


local function power_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  local multiplier = device:get_field(constants.ELECTRICAL_MEASUREMENT_MULTIPLIER_KEY) or 1
  local divisor = 10

  raw_value = raw_value * multiplier / divisor
  device:emit_event(capabilities.powerMeter.power({ value = raw_value, unit = "W" }))
end

local robb_dimmer_handler = {
  NAME = "ROBB smarrt dimmer",
  zigbee_handlers = {
    attr = {
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.InstantaneousDemand.ID] = power_meter_handler
      }
    }
  },
  lifecycle_handlers = {
    init = do_init
  },
  can_handle = is_robb_dimmer
}

return robb_dimmer_handler
