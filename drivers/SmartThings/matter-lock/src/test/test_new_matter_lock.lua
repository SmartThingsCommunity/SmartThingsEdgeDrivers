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
  profile = t_utils.get_profile_definition("lock-user-pin-schedule.yml"),
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
          cluster_id = DoorLock.ID,
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

local DlAlarmCode = DoorLock.types.DlAlarmCode
test.register_message_test(
  "Handle DoorLockAlarm event from Matter device.", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        DoorLock.events.DoorLockAlarm:build_test_event_report(
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
        DoorLock.events.DoorLockAlarm:build_test_event_report(
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
        DoorLock.events.DoorLockAlarm:build_test_event_report(
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
        DoorLock.events.DoorLockAlarm:build_test_event_report(
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
        DoorLock.events.DoorLockAlarm:build_test_event_report(
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
  end
)

test.register_coroutine_test(
  "Handle delete User command received from SmartThings.",
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
  end
)

test.register_coroutine_test(
  "Handle delete all Users command received from SmartThings.",
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
          mock_device, 1, -- endpoint_id
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
          mock_device, 1, -- endpoint_id
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
  end
)

test.run_registered_tests()
