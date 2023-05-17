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
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local constants = require "st.zigbee.constants"
local configurationMap = require "configurations"

local function device_init(driver, device)
  local configuration = configurationMap.get_device_configuration(device)

  if configuration then
    for _, config in ipairs(configuration) do
      if config.use_battery_linear_voltage_handling then
        battery_defaults.build_linear_voltage_init(config.minV, config.maxV)(driver, device)
      elseif config.use_battery_voltage_table and config.battery_voltage_table then
        battery_defaults.enable_battery_voltage_table(device, config.battery_voltage_table)
      elseif (config.cluster) then
        device:add_configured_attribute(config)
        device:add_monitored_attribute(config)
      end
    end
  end
end

local zigbee_water_driver_template = {
  supported_capabilities = {
    capabilities.waterSensor,
    capabilities.temperatureAlarm,
    capabilities.temperatureMeasurement,
    capabilities.battery,
  },
  lifecycle_handlers = {
    init = device_init
  },
  ias_zone_configuration_method = constants.IAS_ZONE_CONFIGURE_TYPE.AUTO_ENROLL_RESPONSE,
  sub_drivers = {
    require("aqara"),
    require("zigbee-water-freeze"),
    require("leaksmart"),
    require("frient"),
    require("thirdreality")
  },
}

defaults.register_for_default_handlers(zigbee_water_driver_template, zigbee_water_driver_template.supported_capabilities)
local zigbee_water_driver = ZigbeeDriver("zigbee-water", zigbee_water_driver_template)
zigbee_water_driver:run()
