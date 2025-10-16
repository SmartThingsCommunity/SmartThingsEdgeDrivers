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

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local json = require "st.json"

-- This test attempts to add a zwave device to this zigbee switch driver
-- Once the monkey-patch is removed with hubcore 59 is released with:
-- https://smartthings.atlassian.net/browse/CHAD-16552
local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("on-off-level.yml"),
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

-- Just validating that the driver doesn't crash is enough to validate
-- that the work-around is effective in ignoring the incorrect device kind
test.register_coroutine_test("zwave_device_handled", function()
    test.mock_device.add_test_device(mock_device)
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    mock_device:expect_metadata_update({provisioning_state = "PROVISIONED"})
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", json.encode(mock_device.raw_st_data) })
    test.wait_for_events()
  end,
  nil
)

test.register_message_test(
  "Capability command for incorrect protocol",
  {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
  }
)

test.run_registered_tests()
