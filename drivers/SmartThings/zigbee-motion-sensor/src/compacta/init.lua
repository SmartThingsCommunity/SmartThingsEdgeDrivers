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

-- ZCL
local zcl_clusters = require "st.zigbee.zcl.clusters"
local TemperatureMeasurement = zcl_clusters.TemperatureMeasurement

local COMPACTA_TEMP_CONFIG = {
  minimum_interval = 30,
  maximum_interval = 300,
  reportable_change = 100,
  endpoint = 0x03
}

local function do_configure(driver, device)
  device:configure()
  device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
    device,
    COMPACTA_TEMP_CONFIG.minimum_interval,
    COMPACTA_TEMP_CONFIG.maximum_interval,
    COMPACTA_TEMP_CONFIG.reportable_change
  ):to_endpoint(COMPACTA_TEMP_CONFIG.endpoint))
end

local function added_handler(driver, device)
  device:refresh()
end

local compacta_driver = {
  NAME = "Compacta Sensor",
  lifecycle_handlers = {
    added = added_handler,
    doConfigure = do_configure
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Compacta"
  end
}

return compacta_driver
