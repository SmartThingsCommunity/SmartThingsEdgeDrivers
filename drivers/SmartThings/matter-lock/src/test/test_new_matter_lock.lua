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
local lock_utils = require "lock_utils"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("lock-user-pin-schedule.yml"),
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
          feature_map = 0x0181, -- PIN & USR & COTA
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
  subscribe_request:merge(DoorLock.attributes.NumberOfTotalUsersSupported:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.NumberOfPINUsersSupported:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.MaxPINCodeLength:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.MinPINCodeLength:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.RequirePINforRemoteOperation:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.NumberOfWeekDaySchedulesSupportedPerUser:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.NumberOfYearDaySchedulesSupportedPerUser:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.LockOperation:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.DoorLockAlarm:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.LockUserChange:subscribe(mock_device))
  test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Assert profile applied over doConfigure",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    mock_device:expect_metadata_update({ profile = "lock-user-pin" })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
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
      mock_device:generate_test_message("main", capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
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
      mock_device:generate_test_message("main", capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
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

test.register_coroutine_test(
  "Handle received NumberOfTotalUsersSupported from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.NumberOfTotalUsersSupported:build_test_report_data(
          mock_device, 1, DoorLock.attributes.NumberOfTotalUsersSupported(10)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockUsers.totalUsersSupported(10, {visibility = {displayed = false}}))
    )
  end
)

test.register_coroutine_test(
  "Handle received NumberOfPINUsersSupported from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.NumberOfPINUsersSupported:build_test_report_data(
          mock_device, 1, DoorLock.attributes.NumberOfPINUsersSupported(10)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockCredentials.pinUsersSupported(10, {visibility = {displayed = false}}))
    )
  end
)

test.register_coroutine_test(
  "Handle received MinPINCodeLength from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.MinPINCodeLength:build_test_report_data(
          mock_device, 1, DoorLock.attributes.MinPINCodeLength(6)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockCredentials.minPinCodeLen(6, {visibility = {displayed = false}}))
    )
  end
)

test.register_coroutine_test(
  "Handle received MaxPINCodeLength from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.MaxPINCodeLength:build_test_report_data(
          mock_device, 1, DoorLock.attributes.MaxPINCodeLength(8)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockCredentials.maxPinCodeLen(8, {visibility = {displayed = false}}))
    )
  end
)

test.register_coroutine_test(
  "Handle received NumberOfWeekDaySchedulesSupportedPerUser from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.NumberOfWeekDaySchedulesSupportedPerUser:build_test_report_data(
          mock_device, 1, DoorLock.attributes.NumberOfWeekDaySchedulesSupportedPerUser(5)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockSchedules.weekDaySchedulesPerUser(5, {visibility = {displayed = false}}))
    )
  end
)

test.register_coroutine_test(
  "Handle received NumberOfYearDaySchedulesSupportedPerUser from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.NumberOfYearDaySchedulesSupportedPerUser:build_test_report_data(
          mock_device, 1, DoorLock.attributes.NumberOfYearDaySchedulesSupportedPerUser(5)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockSchedules.yearDaySchedulesPerUser(5, {visibility = {displayed = false}}))
    )
  end
)

test.register_coroutine_test(
  "Handle received RequirePINforRemoteOperation(true) from Matter device.",
  function()
    test.socket.matter:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.RequirePINforRemoteOperation:build_test_report_data(
          mock_device, 1, DoorLock.attributes.RequirePINforRemoteOperation(true)
        ),
      }
    )
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.mock_time.advance_time(1)
    test.wait_for_events()
    mock_device:set_field(lock_utils.COTA_CRED, "654123", {persist = true}) --overwrite random cred for test expectation
    test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")

    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetCredential(
          mock_device, 1, -- endpoint
          DoorLock.types.DataOperationTypeEnum.ADD, -- operation_type
          DoorLock.types.CredentialStruct(
            {credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = 1}
          ), -- credential
          "654123", -- credential_data
          nil, -- user_index
          DoorLock.types.UserStatusEnum.OCCUPIED_ENABLED, -- user_status
          DoorLock.types.UserTypeEnum.REMOTE_ONLY_USER -- user_type
        ),
      }
    )
    test.mock_time.advance_time(1)
    test.wait_for_events()

    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
          mock_device, 1,
          DoorLock.types.DlStatus.OCCUPIED, -- status
          nil, -- user_index
          2 -- next_credential_index
        ),
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetCredential(
          mock_device, 1, -- endpoint
          DoorLock.types.DataOperationTypeEnum.ADD, -- operation_type
          DoorLock.types.CredentialStruct(
            {credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = 2}
          ), -- credential
          "654123", -- credential_data
          nil, -- user_index
          nil, -- user_status
          DoorLock.types.UserTypeEnum.REMOTE_ONLY_USER -- user_type
        ),
      }
    )
  end
)

test.register_coroutine_test(
"Handle for duplicated pincode during COTA setting",
function()
  test.socket.matter:__set_channel_ordering("relaxed")
  test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      DoorLock.attributes.RequirePINforRemoteOperation:build_test_report_data(
        mock_device, 1, DoorLock.attributes.RequirePINforRemoteOperation(true)
      ),
    }
  )
  test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
  test.mock_time.advance_time(1)
  test.wait_for_events()
  mock_device:set_field(lock_utils.COTA_CRED, "654123", {persist = true}) --overwrite random cred for test expectation
  test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")

  test.socket.matter:__expect_send(
    {
      mock_device.id,
      DoorLock.server.commands.SetCredential(
        mock_device, 1, -- endpoint
        DoorLock.types.DataOperationTypeEnum.ADD, -- operation_type
        DoorLock.types.CredentialStruct(
          {credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = 1}
        ), -- credential
        "654123", -- credential_data
        nil, -- user_index
        DoorLock.types.UserStatusEnum.OCCUPIED_ENABLED, -- user_status
        DoorLock.types.UserTypeEnum.REMOTE_ONLY_USER -- user_type
      ),
    }
  )
  test.mock_time.advance_time(1)
  test.wait_for_events()

  test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")

  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
        mock_device, 1,
        DoorLock.types.DlStatus.DUPLICATE, -- status
        1, -- user_index
        2 -- next_credential_index
      ),
    }
  )
  test.timer.__create_and_queue_test_time_advance_timer(11, "oneshot")
  test.mock_time.advance_time(10) --trigger remote pin handling
  test.wait_for_events()
  mock_device:set_field(lock_utils.COTA_CRED, "654123", {persist = true}) --overwrite random cred for test expectation
  test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")

  test.socket.matter:__expect_send(
    {
      mock_device.id,
      DoorLock.server.commands.SetCredential(
        mock_device, 1, -- endpoint
        DoorLock.types.DataOperationTypeEnum.ADD, -- operation_type
        DoorLock.types.CredentialStruct(
          {credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = 1}
        ), -- credential
        "654123", -- credential_data
        nil, -- user_index
        DoorLock.types.UserStatusEnum.OCCUPIED_ENABLED, -- user_status
        DoorLock.types.UserTypeEnum.REMOTE_ONLY_USER -- user_type
      ),
    }
  )
  test.mock_time.advance_time(1)
  test.wait_for_events()
end
)

test.register_coroutine_test(
  "Handle received RequirePINforRemoteOperation(false) from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.RequirePINforRemoteOperation:build_test_report_data(
          mock_device, 1, DoorLock.attributes.RequirePINforRemoteOperation(false)
        ),
      }
    )
  end
)

test.register_coroutine_test(
  "UnlockDoor uses cota cred when present",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = capabilities.lock.ID, command = "unlock", args = {}}
      }
    )
    mock_device:set_field(lock_utils.COTA_CRED, "654123")
    test.socket.matter:__expect_send({
        mock_device.id,
        clusters.DoorLock.server.commands.UnlockDoor(mock_device, 1, "654123"),
      })
  end
)

test.register_coroutine_test(
  "LockDoor uses cota cred when present", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = capabilities.lock.ID, command = "lock", args = {}}
      }
    )
    mock_device:set_field(lock_utils.COTA_CRED, "654123")
    test.socket.matter:__expect_send({
        mock_device.id,
        clusters.DoorLock.server.commands.LockDoor(mock_device, 1, "654123"),
      })
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
  "Handle received LockState.NOT_FULLY_LOCKED from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.LockState:build_test_report_data(
          mock_device, 1, DoorLock.attributes.LockState.NOT_FULLY_LOCKED
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
  local req = DoorLock.attributes.LockState:read(dev)
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

local AlarmCodeEnum = DoorLock.types.AlarmCodeEnum
test.register_message_test(
  "Handle DoorLockAlarm event from Matter device.", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        DoorLock.events.DoorLockAlarm:build_test_event_report(
          mock_device, 1, {alarm_code = AlarmCodeEnum.LOCK_JAMMED}
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
        DoorLock.events.DoorLockAlarm:build_test_event_report(
          mock_device, 1, {alarm_code = AlarmCodeEnum.LOCK_FACTORY_RESET}
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
        DoorLock.events.DoorLockAlarm:build_test_event_report(
          mock_device, 1, {alarm_code = AlarmCodeEnum.WRONG_CODE_ENTRY_LIMIT}
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
        DoorLock.events.DoorLockAlarm:build_test_event_report(
          mock_device, 1, {alarm_code = AlarmCodeEnum.FRONT_ESCEUTCHEON_REMOVED}
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
        DoorLock.events.DoorLockAlarm:build_test_event_report(
          mock_device, 1, {alarm_code = AlarmCodeEnum.DOOR_FORCED_OPEN}
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

test.register_message_test(
  "Handle Lock Operation event from Matter device.", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        DoorLock.events.LockOperation:build_test_event_report(
          mock_device, 1,
          {
            lock_operation_type = types.LockOperationTypeEnum.UNLOCK,
            operation_source = types.OperationSourceEnum.KEYPAD,
            user_index = 1,
            fabric_index = 1,
            source_node = 1,
            DoorLock.types.CredentialStruct(
              {credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = 1}
            )
          }
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main",
        capabilities.lock.lock.unlocked(
          {data = {method = "keypad", userIndex = 1}, state_change = true}
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
            lock_operation_type = types.LockOperationTypeEnum.LOCK,
            operation_source = types.OperationSourceEnum.UNSPECIFIED,
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
        capabilities.lock.lock.locked(
          {data = {userIndex = 1}, state_change = true}
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
            lock_operation_type = types.LockOperationTypeEnum.UNLOCK,
            operation_source = types.OperationSourceEnum.PROPRIETARY_REMOTE,
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
        capabilities.lock.lock.unlocked(
          {data = {method = "proprietaryRemote", userIndex = 1}, state_change = true}
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
            lock_operation_type = types.LockOperationTypeEnum.LOCK,
            operation_source = types.OperationSourceEnum.AUTO,
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
        capabilities.lock.lock.locked(
          {data = {method = "auto", userIndex = 1}, state_change = true}
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
            lock_operation_type = types.LockOperationTypeEnum.UNLOCK,
            operation_source = types.OperationSourceEnum.SCHEDULE,
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
        capabilities.lock.lock.unlocked(
          {data = {userIndex = 1}, state_change = true}
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
            lock_operation_type = types.LockOperationTypeEnum.LOCK,
            operation_source = types.OperationSourceEnum.REMOTE,
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
        capabilities.lock.lock.locked(
          {data = {method = "command", userIndex = 1}, state_change = true}
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
            lock_operation_type = types.LockOperationTypeEnum.UNLOCK,
            operation_source = types.OperationSourceEnum.BIOMETRIC,
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
        capabilities.lock.lock.unlocked(
          {data = {method = "keypad", userIndex = 1}, state_change = true}
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
            lock_operation_type = types.LockOperationTypeEnum.UNLOCK,
            operation_source = types.OperationSourceEnum.ALIRO,
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
        capabilities.lock.lock.unlocked(
          {data = {userIndex = 1}, state_change = true}
        )
      ),
    }
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

test.register_coroutine_test(
  "Handle Add User command received from SmartThings.",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "addUser",
        args = {"Guest1", "adminMember"}
      },
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.GetUser(
        mock_device, 1,
        1 -- user_index
      )
    })
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.GetUserResponse:build_test_command_response(
        mock_device, 1,
        1, --user_index
        nil, nil, nil, nil, nil, nil, nil, nil, nil
      ),
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetUser(
        mock_device, 1,
        types.DataOperationTypeEnum.ADD,
        1,
        "Guest1",
        nil,
        nil,
        types.UserTypeEnum.UNRESTRICTED_USER,
        nil
      )
    })
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.server.commands.SetUser:build_test_command_response(
          mock_device, 1
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users({{userIndex = 1, userType = "adminMember"}}, {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          {commandName="addUser", statusCode="success", userIndex=1},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Add User command received from SmartThings and commandResult is busy",
  function()
    mock_device:set_field(lock_utils.BUSY_STATE, os.time(), {persist = true})
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "addUser",
        args = {"Guest1", "adminMember"}
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          {commandName="addUser", statusCode="busy"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Handle Add User command received from SmartThings and commandResult is resourceExhausted",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "addUser",
        args = {"Guest1", "adminMember"}
      },
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.GetUser(
        mock_device, 1,
        1 -- user_index
      )
    })
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.GetUserResponse:build_test_command_response(
        mock_device, 1,
        10, --user_index
        nil, nil,
        DoorLock.types.UserStatusEnum.OCCUPIED_ENABLED, --user_state
        nil, nil, nil, nil, nil, nil
      ),
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          {commandName="addUser", statusCode="resourceExhausted", userIndex=10},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Handle Update User command received from SmartThings.",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "updateUser",
        args = {1, "Guest1", "adminMember"}
      },
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetUser(
        mock_device, 1,
        types.DataOperationTypeEnum.MODIFY,
        1,
        "Guest1",
        nil,
        nil,
        types.UserTypeEnum.UNRESTRICTED_USER,
        nil
      )
    })
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.server.commands.SetUser:build_test_command_response(
          mock_device, 1
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          {commandName="updateUser", statusCode="success", userIndex=1},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Update User command received from SmartThings and send busy state",
  function()
    mock_device:set_field(lock_utils.BUSY_STATE, os.time(), {persist = true})
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "updateUser",
        args = {1, "Guest1", "adminMember"}
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          {commandName="updateUser", statusCode="busy"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Handle Delete User command received from SmartThings.",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "deleteUser",
        args = {1}
      },
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.ClearUser(
        mock_device, 1,
        1
      )
    })
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.server.commands.ClearUser:build_test_command_response(
          mock_device, 1
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users({}, {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({}, {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          {commandName="deleteUser", statusCode="success", userIndex=1},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Delete User command received from SmartThings and send busy state",
  function()
    mock_device:set_field(lock_utils.BUSY_STATE, os.time(), {persist = true})
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "deleteUser",
        args = {1}
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          {commandName="deleteUser", statusCode="busy"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Handle Delete All Users command received from SmartThings.",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "deleteAllUsers",
        args = {}
      },
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.ClearUser(
        mock_device, 1,
        0xFFFE
      )
    })
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.server.commands.ClearUser:build_test_command_response(
          mock_device, 1
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users({}, {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({}, {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          {commandName="deleteAllUsers", statusCode="success", userIndex=65534},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Delete All Users command received from SmartThings and send busy state",
  function()
    mock_device:set_field(lock_utils.BUSY_STATE, os.time(), {persist = true})
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "deleteAllUsers",
        args = {}
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          {commandName="deleteAllUsers", statusCode="busy"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Handle Add Credential command received from SmartThings.",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockCredentials.ID,
          command = "addCredential",
          args = {1, "adminMember", "pin", "654123"}
        },
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetCredential(
          mock_device, 1, -- endpoint
          DoorLock.types.DataOperationTypeEnum.ADD, -- operation_type
          DoorLock.types.CredentialStruct(
            {credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = 1}
          ), -- credential
          "654123", -- credential_data
          1, -- user_index
          nil, -- user_status
          DoorLock.types.DlUserType.UNRESTRICTED_USER -- user_type
        ),
      }
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
          mock_device, 1,
          DoorLock.types.DlStatus.SUCCESS, -- status
          1, -- user_index
          2 -- next_credential_index
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials(
          {{credentialIndex=1, credentialType="pin", userIndex=1}},
          {visibility={displayed=false}}
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          {commandName="addCredential", credentialIndex=1, statusCode="success", userIndex=1},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Add Credential command received from SmartThings and commandResult is busy",
  function()
    mock_device:set_field(lock_utils.BUSY_STATE, os.time(), {persist = true})
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockCredentials.ID,
          command = "addCredential",
          args = {1, "adminMember", "pin", "654123"}
        },
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          {commandName="addCredential", statusCode="busy"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Add Credential command received from SmartThings and commandResult is invalidCommand",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockCredentials.ID,
          command = "addCredential",
          args = {1, "adminMember", "pin", "654123"}
        },
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetCredential(
          mock_device, 1, -- endpoint
          DoorLock.types.DataOperationTypeEnum.ADD, -- operation_type
          DoorLock.types.CredentialStruct(
            {credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = 1}
          ), -- credential
          "654123", -- credential_data
          1, -- user_index
          nil, -- user_status
          DoorLock.types.DlUserType.UNRESTRICTED_USER -- user_type
        ),
      }
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
          mock_device, 1,
          DoorLock.types.DlStatus.INVALID_FIELD, -- status
          1, -- user_index
          2 -- next_credential_index
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          {commandName="addCredential", statusCode="invalidCommand"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Add Credential command received from SmartThings and user_index is occupied",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockCredentials.ID,
          command = "addCredential",
          args = {1, "adminMember", "pin", "654123"}
        },
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetCredential(
          mock_device, 1, -- endpoint
          DoorLock.types.DataOperationTypeEnum.ADD, -- operation_type
          DoorLock.types.CredentialStruct(
            {credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = 1}
          ), -- credential
          "654123", -- credential_data
          1, -- user_index
          nil, -- user_status
          DoorLock.types.DlUserType.UNRESTRICTED_USER -- user_type
        ),
      }
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
          mock_device, 1,
          DoorLock.types.DlStatus.OCCUPIED, -- status
          1, -- user_index
          2 -- next_credential_index
        ),
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetCredential(
          mock_device, 1, -- endpoint
          DoorLock.types.DataOperationTypeEnum.ADD, -- operation_type
          DoorLock.types.CredentialStruct(
            {credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = 2}
          ), -- credential
          "654123", -- credential_data
          1, -- user_index
          nil, -- user_status
          DoorLock.types.DlUserType.UNRESTRICTED_USER -- user_type
        ),
      }
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Add Credential command received from SmartThings and commandResult is resourceExhausted",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockCredentials.ID,
          command = "addCredential",
          args = {1, "adminMember", "pin", "654123"}
        },
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetCredential(
          mock_device, 1, -- endpoint
          DoorLock.types.DataOperationTypeEnum.ADD, -- operation_type
          DoorLock.types.CredentialStruct(
            {credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = 1}
          ), -- credential
          "654123", -- credential_data
          1, -- user_index
          nil, -- user_status
          DoorLock.types.DlUserType.UNRESTRICTED_USER -- user_type
        ),
      }
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
          mock_device, 1,
          DoorLock.types.DlStatus.OCCUPIED, -- status
          1, -- user_index
          nil -- next_credential_index
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          {commandName="addCredential", statusCode="resourceExhausted"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Handle Update Credential command received from SmartThings.",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockCredentials.ID,
          command = "updateCredential",
          args = {1, 1, "pin", "654123"}
        },
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetCredential(
          mock_device, 1, -- endpoint
          DoorLock.types.DataOperationTypeEnum.MODIFY, -- operation_type
          DoorLock.types.CredentialStruct(
            {credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = 1}
          ), -- credential
          "654123", -- credential_data
          1, -- user_index
          nil, -- user_status
          nil -- user_type
        ),
      }
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
          mock_device, 1,
          DoorLock.types.DlStatus.SUCCESS, -- status
          1, -- user_index
          2 -- next_credential_index
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          {commandName="updateCredential", credentialIndex=1, statusCode="success", userIndex=1},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Update Credential command received from SmartThings and send busy state",
  function()
    mock_device:set_field(lock_utils.BUSY_STATE, os.time(), {persist = true})
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockCredentials.ID,
          command = "updateCredential",
          args = {1, 1, "pin", "654123"}
        },
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          {commandName="updateCredential", statusCode="busy"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Handle Delete Credential command received from SmartThings.",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockCredentials.ID,
          command = "deleteCredential",
          args = {1, "pin"}
        },
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.ClearCredential(
          mock_device, 1, -- endpoint
          DoorLock.types.CredentialStruct(
            {credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = 1}
          )
        ),
      }
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.server.commands.ClearCredential:build_test_command_response(
          mock_device, 1
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({}, {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          {commandName="deleteCredential", credentialIndex=1, statusCode="success"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Delete Credential command received from SmartThings and send busy state",
  function()
    mock_device:set_field(lock_utils.BUSY_STATE, os.time(), {persist = true})
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockCredentials.ID,
          command = "deleteCredential",
          args = {1, "pin"}
        },
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          {commandName="deleteCredential", statusCode="busy"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Handle Delete all Credentials command received from SmartThings.",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockCredentials.ID,
          command = "deleteAllCredentials",
          args = {"pin"}
        },
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.ClearCredential(
          mock_device, 1, -- endpoint
          DoorLock.types.CredentialStruct(
            {credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = 0xFFFE}
          )
        ),
      }
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.server.commands.ClearCredential:build_test_command_response(
          mock_device, 1
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({}, {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          {commandName="deleteAllCredentials", credentialIndex=65534, statusCode="success"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Delete all Credentials command received from SmartThings and send busy state",
  function()
    mock_device:set_field(lock_utils.BUSY_STATE, os.time(), {persist = true})
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockCredentials.ID,
          command = "deleteAllCredentials",
          args = {"pin"}
        },
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          {commandName="deleteAllCredentials", statusCode="busy"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Handle Add Week Day Schedule command received from SmartThings.",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockSchedules.ID,
          command = "setWeekDaySchedule",
          args = {1, 1, {weekDays={"Monday"}, startHour=12, startMinute=30, endHour=17, endMinute=30}}
        },
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetWeekDaySchedule(
          mock_device, 1, -- endpoint
          1, -- Week Day Schedule Index
          1, -- User Index
          2, -- Days Mask
          12, -- Start Hour
          30, -- Start Minute
          17, -- End Hour
          30 -- End Minute
        ),
      }
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.server.commands.SetWeekDaySchedule:build_test_command_response(
          mock_device, 1
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockSchedules.weekDaySchedules(
          {{
            userIndex=1,
            schedules={{
              scheduleIndex=1,
              weekdays={"Monday"},
              startHour=12,
              startMinute=30,
              endHour=17,
              endMinute=30
            }},
          }},
          {visibility={displayed=false}}
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockSchedules.commandResult(
          {commandName="setWeekDaySchedule", userIndex=1, scheduleIndex=1, statusCode="success"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Add Week Day Schedule command received from SmartThings and send busy state",
  function()
    mock_device:set_field(lock_utils.BUSY_STATE, os.time(), {persist = true})
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockSchedules.ID,
          command = "setWeekDaySchedule",
          args = {1, 1, {weekDays={"Monday"}, startHour=12, startMinute=30, endHour=17, endMinute=30}}
        },
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockSchedules.commandResult(
          {commandName="setWeekDaySchedule", statusCode="busy"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Handle Clear Week Day Schedule command received from SmartThings.",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockSchedules.ID,
          command = "clearWeekDaySchedules",
          args = {
            1, -- user index
            1, -- schedule index
          }
        },
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.ClearWeekDaySchedule(
          mock_device, 1, -- endpoint
          1,  -- schedule index
          1  -- user index
        ),
      }
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.server.commands.ClearWeekDaySchedule:build_test_command_response(
          mock_device, 1
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockSchedules.commandResult(
          {commandName="clearWeekDaySchedules", userIndex = 1, scheduleIndex=1, statusCode="success"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Clear Week Day Schedule command received from SmartThings and send busy state",
  function()
    mock_device:set_field(lock_utils.BUSY_STATE, os.time(), {persist = true})
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockSchedules.ID,
          command = "clearWeekDaySchedules",
          args = {
            1, -- user index
            1, -- schedule index
          }
        },
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockSchedules.commandResult(
          {commandName="clearWeekDaySchedules", statusCode="busy"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.run_registered_tests()
