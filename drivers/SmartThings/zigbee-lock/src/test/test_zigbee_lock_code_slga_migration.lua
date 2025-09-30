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

-- Mock out globals
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = clusters.PowerConfiguration
local DoorLock = clusters.DoorLock
local Alarm = clusters.Alarms
local capabilities = require "st.capabilities"

local json = require "st.json"

local mock_datastore = require "integration_test.mock_env_datastore"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("base-lock.yml"),
      data = {
        lockCodes = json.encode({
          ["1"] = "Zach",
          ["5"] = "Steven"
        }),
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Device called 'migrate' command",
    function()
      test.mock_device.add_test_device(mock_device)
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
      test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, Alarm.attributes.AlarmCount:read(mock_device) })
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device.id, "lockCodes", { ["1"] = "Zach", ["5"] = "Steven" })
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device.id, "migrationComplete", true)

      -- Set min/max code length attributes
      test.socket.zigbee:__queue_receive({ mock_device.id, DoorLock.attributes.MinPINCodeLength:build_test_attr_report(mock_device, 5) })
      test.socket.zigbee:__queue_receive({ mock_device.id, DoorLock.attributes.MaxPINCodeLength:build_test_attr_report(mock_device, 10) })
      test.socket.zigbee:__queue_receive({ mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:build_test_attr_report(mock_device, 4) })
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(5,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(10,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.maxCodes(4,  { visibility = { displayed = false } })))
      test.wait_for_events()
      -- Validate `migrate` command functionality.
      test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "migrate", args = {} } })
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.minPinCodeLen(5,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.maxPinCodeLen(10,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.pinUsersSupported(4,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.credentials({{credentialIndex=1, credentialType="pin", userIndex=1}, {credentialIndex=5, credentialType="pin", userIndex=2}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.supportedCredentials({"pin"},  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockUsers.users({{userIndex=1, userName="Zach", userType="guest"}, {userIndex=2, userName="Steven", userType="guest"}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true,  { visibility = { displayed = false } })))
      test.wait_for_events()
    end
)

test.run_registered_tests()