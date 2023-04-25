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
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local DoorLock = clusters.DoorLock

local mock_device = test.mock_device.build_test_zigbee_device({ profile = t_utils.get_profile_definition("base-lock.yml"), zigbee_endpoints ={ [1] = {id = 1, manufacturer ="ASSA ABLOY iRevo", model ="iZBModule01", server_clusters = {}} } })

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Max user code number report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:build_test_attr_report(mock_device,
                                                                                                           16) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lockCodes.maxCodes(30))
      }
    }
)

test.run_registered_tests()
