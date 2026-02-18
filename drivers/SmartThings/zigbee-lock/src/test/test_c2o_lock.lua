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

local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local ZclStatus = require "st.zigbee.generated.types.ZclStatus"

local PowerConfiguration = clusters.PowerConfiguration
local DoorLock = clusters.DoorLock

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("lock-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = nil,
        model = "E261-KR0B0Z0-HA",
        server_clusters = { 0x0001, 0x0101 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Refresh necessary attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, DoorLock.ID)
    })

    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 30, 21600, 1)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        DoorLock.attributes.LockState:configure_reporting(mock_device, 0, 3600, 1)
      }
    )
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Device added lifecycle event should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Capability (lock) command (lock) should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "lock", component = "main", command = "lock", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.commands.LockDoor(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Capability (lock) command (unlock) should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "lock", component = "main", command = "unlock", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.commands.UnlockDoor(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) })
  end
)

test.register_coroutine_test(
  "DoorLock Lock response message should be handled",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__queue_receive({ mock_device.id, DoorLock.commands.LockDoorResponse.build_test_rx(mock_device, ZclStatus.SUCCESS) })
    test.wait_for_events()
    test.mock_time.advance_time(5)
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:read(mock_device) })
  end
)

test.register_coroutine_test(
  "DoorLock Unlock response message should be handled",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__queue_receive({ mock_device.id, DoorLock.commands.UnlockDoorResponse.build_test_rx(mock_device, ZclStatus.SUCCESS) })
    test.wait_for_events()
    test.mock_time.advance_time(5)
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:read(mock_device) })
  end
)

test.register_coroutine_test(
  "PinUsersSupported report should be a no-op",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:build_test_attr_report(mock_device, 8)})
  end
)

test.run_registered_tests()
