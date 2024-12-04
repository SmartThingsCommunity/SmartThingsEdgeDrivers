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

local test = require "integration_test"
local capabilities = require "st.capabilities"
test.add_package_capability("lockAlarm.yml")
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local DoorLock = clusters.DoorLock
local types = DoorLock.types

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("lock-unlatch.yml"),
  manufacturer_info = {
    vendor_id = 0x115f,
    product_id = 0x2802,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.BasicInformation.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 } -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = DoorLock.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0x1000, -- UNBOLT
        }
      },
      device_types = {
        { device_type_id = 0x000A, device_type_revision = 1 } -- Door Lock
      }
    }
  }
})

local function test_init()
  local subscribe_request = DoorLock.attributes.LockState:subscribe(mock_device)
  subscribe_request:merge(DoorLock.attributes.OperatingMode:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.LockOperation:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.DoorLockAlarm:subscribe(mock_device))
  test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Assert profile applied over doConfigure",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    mock_device:expect_metadata_update({ profile = "lock-unlatch" })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.supportedLockCommands({"lock", "unlock", "unlatch"}, {visibility = {displayed = false}}))
    )
  end
)

test.register_coroutine_test(
  "Handle received OperatingMode(Normal, Vacation) from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.OperatingMode:build_test_report_data(
          mock_device, 1, DoorLock.attributes.OperatingMode.NORMAL
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.remoteControlStatus.remoteControlEnabled("true", {visibility = {displayed = true}}))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.supportedLockCommands({"lock", "unlock", "unlatch"}, {visibility = {displayed = false}}))
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.OperatingMode:build_test_report_data(
          mock_device, 1, DoorLock.attributes.OperatingMode.VACATION
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.remoteControlStatus.remoteControlEnabled("true", {visibility = {displayed = true}}))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.supportedLockCommands({"lock", "unlock", "unlatch"}, {visibility = {displayed = false}}))
    )
  end
)

test.register_coroutine_test(
  "Handle received OperatingMode(Privacy, No Remote Lock UnLock, Passage) from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.OperatingMode:build_test_report_data(
          mock_device, 1, DoorLock.attributes.OperatingMode.PRIVACY
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.remoteControlStatus.remoteControlEnabled("false", {visibility = {displayed = true}}))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.supportedLockCommands({}, {visibility = {displayed = false}}))
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.OperatingMode:build_test_report_data(
          mock_device, 1, DoorLock.attributes.OperatingMode.NO_REMOTE_LOCK_UNLOCK
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.remoteControlStatus.remoteControlEnabled("false", {visibility = {displayed = true}}))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.supportedLockCommands({}, {visibility = {displayed = false}}))
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.OperatingMode:build_test_report_data(
          mock_device, 1, DoorLock.attributes.OperatingMode.PASSAGE
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.remoteControlStatus.remoteControlEnabled("false", {visibility = {displayed = true}}))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.supportedLockCommands({}, {visibility = {displayed = false}}))
    )
  end
)

test.register_message_test(
  "Handle Lock command received from SmartThings.", {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        {capability = "lock", component = "main", command = "lock", args = {}},
      },
    },
    {
      channel = "matter",
      direction = "send",
      message = {mock_device.id, DoorLock.server.commands.LockDoor(mock_device, 1)},
    },
  }
)

test.register_message_test(
  "Handle Unlock command received from SmartThings.", {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        {capability = "lock", component = "main", command = "unlock", args = {}},
      },
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        DoorLock.server.commands.UnboltDoor(mock_device, 1),
      },
    },
  }
)

test.register_message_test(
  "Handle Unlatch command received from SmartThings.", {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        {capability = "lock", component = "main", command = "unlatch", args = {}},
      },
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        DoorLock.server.commands.UnlockDoor(mock_device, 1),
      },
    },
  }
)

test.register_coroutine_test(
  "Handle received LockState.LOCKED from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.LockState:build_test_report_data(
          mock_device, 1, DoorLock.attributes.LockState.LOCKED
        ),
      }
    )
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.mock_time.advance_time(1)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.lock.locked())
    )
  end
)

test.register_coroutine_test(
  "Handle received LockState.UNLOCKED from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.LockState:build_test_report_data(
          mock_device, 1, DoorLock.attributes.LockState.UNLOCKED
        ),
      }
    )
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.mock_time.advance_time(1)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.lock.unlocked())
    )
  end
)

test.register_coroutine_test(
  "Handle received LockState.UNLATCHED from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.LockState:build_test_report_data(
          mock_device, 1, DoorLock.attributes.LockState.UNLATCHED
        ),
      }
    )
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.mock_time.advance_time(1)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.lock.unlatched())
    )
  end
)

test.register_message_test(
  "Handle Unlatch Operation event from Matter device.", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        DoorLock.events.LockOperation:build_test_event_report(
          mock_device, 1,
          {
            lock_operation_type = types.LockOperationTypeEnum.UNLATCH,
            operation_source = types.OperationSourceEnum.MANUAL,
            user_index = 1,
            fabric_index = 1,
            source_node = 1
          }
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main",
        capabilities.lock.lock.unlatched(
          {data = {method = "manual", userIndex = 1}, state_change = true}
        )
      ),
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        DoorLock.events.LockOperation:build_test_event_report(
          mock_device, 1,
          {
            lock_operation_type = types.LockOperationTypeEnum.UNLATCH,
            operation_source = types.OperationSourceEnum.BUTTON,
            user_index = 1,
            fabric_index = 1,
            source_node = 1
          }
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main",
        capabilities.lock.lock.unlatched(
          {data = {method = "button", userIndex = 1}, state_change = true}
        )
      ),
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        DoorLock.events.LockOperation:build_test_event_report(
          mock_device, 1,
          {
            lock_operation_type = types.LockOperationTypeEnum.UNLATCH,
            operation_source = types.OperationSourceEnum.RFID,
            user_index = 1,
            fabric_index = 1,
            source_node = 1
          }
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main",
        capabilities.lock.lock.unlatched(
          {data = {method = "rfid", userIndex = 1}, state_change = true}
        )
      ),
    }
  }
)
test.run_registered_tests()
