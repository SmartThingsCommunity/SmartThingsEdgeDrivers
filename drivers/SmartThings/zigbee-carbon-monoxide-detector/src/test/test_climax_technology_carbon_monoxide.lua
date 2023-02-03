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

-- Mock out globals
local test = require "integration_test"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("carbonMonoxide-battery.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "ClimaxTechnology",
          model = "CO_00.00.00.22TC",
          server_clusters = {0x0000}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end
test.set_test_init_function(test_init)

test.register_message_test(
    "added lifecycle event should get initial state for device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_device.id, "added"}
      },
      -- {
      --   channel = "capability",
      --   direction = "send",
      --   message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
      -- }
    },
    {
      inner_block_ordering = "relaxed"
    }
)


test.run_registered_tests()
