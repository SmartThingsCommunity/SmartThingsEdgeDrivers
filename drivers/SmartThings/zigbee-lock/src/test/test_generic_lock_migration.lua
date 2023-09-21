-- Copyright 2023 SmartThings
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

local mock_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("lock-battery.yml") }
)
zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "If lock codes are not supported by the profile but the lock supports them, switch profiles",
  function ()
    test.socket.capability:__queue_receive({mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} }})

    test.socket.zigbee:__expect_send({mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)})
    test.socket.zigbee:__expect_send({mock_device.id, DoorLock.attributes.LockState:read(mock_device)})
    test.socket.zigbee:__expect_send({mock_device.id, Alarm.attributes.AlarmCount:read(mock_device)})
    test.socket.zigbee:__expect_send({mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:read(mock_device)})
    test.socket.zigbee:__queue_receive({mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:build_test_attr_report(mock_device, 8)})
    mock_device:expect_metadata_update({profile = "base-lock"})
  end
)

test.run_registered_tests()