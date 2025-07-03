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
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local Basic = clusters.Basic

local mock_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("range-extender.yml") }
)

local function test_init()
  test.mock_device.add_test_device(mock_device)  test.timer.__create_and_queue_test_time_advance_timer(600, "interval", "health_check")
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Refresh necessary attributes",
    function()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Basic.attributes.ZCLVersion:read(mock_device)
          }
      )
    end
)

-- test.register_coroutine_test(
--     "Health check should check all relevant attributes",
--     function()
--       test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
--       test.wait_for_events()

--       test.mock_time.advance_time(50000)
--       test.socket.zigbee:__set_channel_ordering("relaxed")
--       test.socket.zigbee:__expect_send({ mock_device.id, Basic.attributes.ZCLVersion:read(mock_device) })
--       test.wait_for_events()
--     end
-- )

test.run_registered_tests()
