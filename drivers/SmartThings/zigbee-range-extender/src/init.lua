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

local Basic = (require "st.zigbee.zcl.clusters").Basic
local ZigbeeDriver = require "st.zigbee"

local do_refresh = function(self, device)
  device:send(Basic.attributes.ZCLVersion:read(device))
end

local zigbee_range_driver_template = {
  supported_capabilities = {
    capabilities.refresh
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  health_check = false,
}

local zigbee_range_extender_driver = ZigbeeDriver("zigbee-range-extender", zigbee_range_driver_template)

function zigbee_range_extender_driver:device_health_check()
  local device_list = self.device_api.get_device_list()
  for _, device_id in ipairs(device_list) do
    local device = self:get_device_info(device_id, false)
    device:send(Basic.attributes.ZCLVersion:read(device))
  end
end
zigbee_range_extender_driver.device_health_timer = zigbee_range_extender_driver.call_on_schedule(zigbee_range_extender_driver, 300, zigbee_range_extender_driver.device_health_check)

zigbee_range_extender_driver:run()
