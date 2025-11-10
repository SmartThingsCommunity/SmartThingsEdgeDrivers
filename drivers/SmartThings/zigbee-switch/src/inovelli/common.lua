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

local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local OTAUpgrade = require("st.zigbee.zcl.clusters").OTAUpgrade

local M = {}

-- Sends a generic configure for Inovelli devices (all models):
-- - device:configure
-- - send OTA ImageNotify
-- - bind PRIVATE cluster for button presses
-- - read metering/electrical measurement divisors/multipliers
function M.base_device_configure(driver, device, private_cluster_id, mfg_code)
  device:configure()
  -- OTA Image Notify (generic for all devices)
  local PAYLOAD_TYPE = 0x00
  local QUERY_JITTER = 100
  local IMAGE_TYPE = 0xFFFF
  local NEW_VERSION  = 0xFFFFFFFF
  device:send(OTAUpgrade.commands.ImageNotify(device, PAYLOAD_TYPE, QUERY_JITTER, mfg_code, IMAGE_TYPE, NEW_VERSION))

  -- Bind for button presses on manufacturer private cluster
  device:send(device_management.build_bind_request(device, private_cluster_id, driver.environment_info.hub_zigbee_eui, 2))

  -- Read divisors/multipliers for power/energy reporting
  device:send(clusters.SimpleMetering.attributes.Divisor:read(device))
  device:send(clusters.SimpleMetering.attributes.Multiplier:read(device))
  device:send(clusters.ElectricalMeasurement.attributes.ACPowerDivisor:read(device))
  device:send(clusters.ElectricalMeasurement.attributes.ACPowerMultiplier:read(device))
end

return M