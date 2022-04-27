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
local OccupancySensing = zcl_clusters.OccupancySensing
local PowerConfiguration = zcl_clusters.PowerConfiguration
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local capabilities = require "st.capabilities"

local FRIENT_TEMP_CONFIG = {
  minimum_interval = 30,
  maximum_interval = 300,
  reportable_change = 100,
  endpoint = 0x26
}

local FRIENT_BATTERY_CONFIG = {
  minimum_interval = 30,
  maximum_interval = 21600,
  reportable_change = 1,
  endpoint = 0x23
}

local function occupancy_attr_handler(driver, device, occupancy, zb_rx)
  device:emit_event(
    occupancy.value == 1 and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive()
  )
end

local function do_configure(driver, device)
  device:configure()
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(
    device,
    FRIENT_BATTERY_CONFIG.minimum_interval,
    FRIENT_BATTERY_CONFIG.maximum_interval,
    FRIENT_BATTERY_CONFIG.reportable_change
  ):to_endpoint(FRIENT_BATTERY_CONFIG.endpoint))
  device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
    device,
    FRIENT_TEMP_CONFIG.minimum_interval,
    FRIENT_TEMP_CONFIG.maximum_interval,
    FRIENT_TEMP_CONFIG.reportable_change
  ):to_endpoint(FRIENT_TEMP_CONFIG.endpoint))
end

local function added_handler(driver, device)
  device:refresh()
end

local frient_driver = {
  NAME = "Frient Sensor",
  zigbee_handlers = {
    attr = {
      [OccupancySensing.ID] = {
        [OccupancySensing.attributes.Occupancy.ID] = occupancy_attr_handler
      }
    }
  },
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.3, 3.0),
    added = added_handler,
    doConfigure = do_configure
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "frient A/S"
  end
}

return frient_driver
