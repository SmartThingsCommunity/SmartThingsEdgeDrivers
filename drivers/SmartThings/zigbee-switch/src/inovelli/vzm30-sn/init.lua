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
local st_device = require "st.device"
local inovelli_common = require "inovelli.common"

local TemperatureMeasurement = clusters.TemperatureMeasurement
local RelativeHumidity = clusters.RelativeHumidity

local INOVELLI_VZM30_SN_FINGERPRINTS = {
  { mfr = "Inovelli", model = "VZM30-SN" },
}

local PRIVATE_CLUSTER_ID = 0xFC31
local MFG_CODE = 0x122F

local function can_handle_inovelli_vzm30_sn(opts, driver, device)
  for _, fp in ipairs(INOVELLI_VZM30_SN_FINGERPRINTS) do
    if device:get_manufacturer() == fp.mfr and device:get_model() == fp.model then
      return true
    end
  end
  return false
end

local function configure_temperature_reporting(device)
  local min_temp_change = 50  -- 0.5°C in 0.01°C units
  device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(device, 30, 3600, min_temp_change))
end

local function configure_humidity_reporting(device)
  local min_humidity_change = 50  -- 0.5% in 0.01% units
  device:send(RelativeHumidity.attributes.MeasuredValue:configure_reporting(device, 30, 3600, min_humidity_change))
end

local function device_configure(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    inovelli_common.base_device_configure(driver, device, PRIVATE_CLUSTER_ID, MFG_CODE)
    configure_temperature_reporting(device)
    configure_humidity_reporting(device)
  else
    device:configure()
  end
end

local vzm30_sn = {
  NAME = "inovelli vzm30-sn device-specific",
  can_handle = can_handle_inovelli_vzm30_sn,
  lifecycle_handlers = {
    doConfigure = device_configure,
  },
}

return vzm30_sn