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

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("lock-user-pin.yml"),
  manufacturer_info = {
    vendor_id = 0x115f,
    product_id = 0x2802,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 } -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.DoorLock.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0x0001, --u32 bitmap
        }
      },
      device_types = {
        { device_type_id = 0x000A, device_type_revision = 1 } -- Door Lock
      }
    }
  }
})

local function test_init()
  local subscribe_request = clusters.DoorLock.attributes.LockState:subscribe(mock_device)
  subscribe_request:merge(clusters.DoorLock.attributes.OperatingMode:subscribe(mock_device))
  subscribe_request:merge(clusters.DoorLock.attributes.NumberOfTotalUsersSupported:subscribe(mock_device))
  subscribe_request:merge(clusters.DoorLock.attributes.NumberOfPINUsersSupported:subscribe(mock_device))
  subscribe_request:merge(clusters.DoorLock.attributes.MaxPINCodeLength:subscribe(mock_device))
  subscribe_request:merge(clusters.DoorLock.attributes.MinPINCodeLength:subscribe(mock_device))
  subscribe_request:merge(clusters.DoorLock.attributes.RequirePINforRemoteOperation:subscribe(mock_device))
  subscribe_request:merge(clusters.DoorLock.events.LockOperation:subscribe(mock_device))
  subscribe_request:merge(clusters.DoorLock.events.DoorLockAlarm:subscribe(mock_device))
  subscribe_request:merge(clusters.DoorLock.events.LockUserChange:subscribe(mock_device))
  test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

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
      message = {mock_device.id, clusters.DoorLock.server.commands.LockDoor(mock_device, 1)},
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
        clusters.DoorLock.server.commands.UnlockDoor(mock_device, 1),
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
        clusters.DoorLock.attributes.LockState:build_test_report_data(
          mock_device, 1, clusters.DoorLock.attributes.LockState.LOCKED
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
        clusters.DoorLock.attributes.LockState:build_test_report_data(
          mock_device, 1, clusters.DoorLock.attributes.LockState.UNLOCKED
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
  "Handle received LockState.NOT_FULLY_LOCKED from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.DoorLock.attributes.LockState:build_test_report_data(
          mock_device, 1, clusters.DoorLock.attributes.LockState.NOT_FULLY_LOCKED
        ),
      }
    )
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.mock_time.advance_time(1)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.lock.not_fully_locked())
    )
  end
)

local function refresh_commands(dev)
  local req = clusters.DoorLock.attributes.LockState:read(dev)
  return req
end

test.register_message_test(
  "Handle received refresh.", {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        {capability = "refresh", component = "main", command = "refresh", args = {}},
      },
    },
    {
      channel = "matter",
      direction = "send",
      message = {mock_device.id, refresh_commands(mock_device)},
    },
  }
)

local DlAlarmCode = clusters.DoorLock.types.DlAlarmCode
test.register_message_test(
  "Handle DoorLockAlarm event from Matter device.", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DoorLock.events.DoorLockAlarm:build_test_event_report(
          mock_device, 1, {alarm_code = DlAlarmCode.LOCK_JAMMED}
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main",
        capabilities.lockAlarm.alarm.unableToLockTheDoor({state_change = true})
      ),
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DoorLock.events.DoorLockAlarm:build_test_event_report(
          mock_device, 1, {alarm_code = DlAlarmCode.LOCK_FACTORY_RESET}
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main",
        capabilities.lockAlarm.alarm.lockFactoryReset({state_change = true})
      ),
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DoorLock.events.DoorLockAlarm:build_test_event_report(
          mock_device, 1, {alarm_code = DlAlarmCode.WRONG_CODE_ENTRY_LIMIT}
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main",
        capabilities.lockAlarm.alarm.attemptsExceeded({state_change = true})
      ),
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DoorLock.events.DoorLockAlarm:build_test_event_report(
          mock_device, 1, {alarm_code = DlAlarmCode.FRONT_ESCEUTCHEON_REMOVED}
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main",
        capabilities.lockAlarm.alarm.damaged({state_change = true})
      ),
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DoorLock.events.DoorLockAlarm:build_test_event_report(
          mock_device, 1, {alarm_code = DlAlarmCode.DOOR_FORCED_OPEN}
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main",
        capabilities.lockAlarm.alarm.forcedOpeningAttempt({state_change = true})
      ),
    },
  }
)

test.register_coroutine_test(
  "Added lifecycle event lock nocodes nobattery",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAlarm.alarm.clear({state_change = true})
      )
    )
end
)

test.run_registered_tests()
