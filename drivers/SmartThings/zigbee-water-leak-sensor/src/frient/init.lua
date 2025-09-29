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
local TemperatureMeasurement = clusters.TemperatureMeasurement
local configurationMap = require "configurations"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local function device_init(driver, device)
  local configuration = configurationMap.get_device_configuration(device)

  if configuration then
    for _, config in ipairs(configuration) do
      if config.use_battery_linear_voltage_handling then
        battery_defaults.build_linear_voltage_init(config.minV, config.maxV)(driver, device)
      elseif (config.cluster) then
        device:add_configured_attribute(config)
      end
    end
  end
end

local function do_configure(driver, device)
  device:configure()
  device:send(TemperatureMeasurement.server.attributes.MeasuredValue:configure_reporting(device, 60, 600, 100):to_endpoint(0x26))
  device:refresh()
end

local frient_water_leak_sensor = {
  NAME = "frient water leak sensor",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "frient A/S" and device:get_model() == "FLSZB-110"
  end
}

return frient_water_leak_sensor
