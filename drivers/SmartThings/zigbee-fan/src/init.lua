-- Copyright 2024 SmartThings
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
local configurationMap = require "configurations"

local device_init = function(self, device)
  local configuration = configurationMap.get_device_configuration(device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end
end

local zigbee_fan_driver = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.fanspeed
  },
  sub_drivers = {
    require("fan-light")
  },
  lifecycle_handlers = {
    init = device_init
  }
}

defaults.register_for_default_handlers(zigbee_fan_driver,zigbee_fan_driver.supported_capabilities)
local fan = ZigbeeDriver("zigbee-fan", zigbee_fan_driver)
fan:run()

