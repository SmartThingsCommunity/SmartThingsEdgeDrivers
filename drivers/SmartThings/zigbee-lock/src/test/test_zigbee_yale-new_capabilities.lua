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
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local PowerConfiguration = clusters.PowerConfiguration
local Alarm = clusters.Alarms

local DoorLock = clusters.DoorLock
local DoorLockUserStatus = DoorLock.types.DrlkUserStatus
local DoorLockUserType = DoorLock.types.DrlkUserType
local ProgrammingEventCode = DoorLock.types.ProgramEventCode


local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("base-lock.yml"),
  zigbee_endpoints = {
    [1] = { id = 1, manufacturer = "Yale", server_clusters = { 0x0001 } }
  }
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init_default()
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockCodes.migrated(true, { state_change = true, visibility = { displayed = true } })))
  test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(
    mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, Alarm.attributes.AlarmCount:read(mock_device) })
end

local function test_init_add_device()
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockCodes.migrated(true, { state_change = true, visibility = { displayed = true } })))
  test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(
    mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, Alarm.attributes.AlarmCount:read(mock_device) })

  test.socket.zigbee:__queue_receive({ mock_device.id, DoorLock.attributes.MinPINCodeLength:build_test_attr_report(
    mock_device, 4) })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockCredentials.minPinCodeLen(4, { visibility = { displayed = false } })))
  test.socket.zigbee:__queue_receive({ mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported
      :build_test_attr_report(mock_device, 4) })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockUsers.totalUsersSupported(4, { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockCredentials.pinUsersSupported(4, { visibility = { displayed = false } })))
end

test.set_test_init_function(test_init_default)

local expect_reload_all_codes_messages = function()
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.SendPINOverTheAir:write(mock_device,
    true) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.MaxPINCodeLength:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.MinPINCodeLength:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.NumberOfTotalUsersSupported:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.GetPINCode(mock_device, 1) })
  test.socket.zigbee:__queue_receive({
    mock_device.id,
    DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
      mock_device,
      0x01,
      DoorLockUserType.UNRESTRICTED,
      DoorLockUserStatus.AVAILABLE,
      ""
    )
  })
end

test.register_coroutine_test(
  "Configure should configure all necessary attributes and begin reading codes",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.wait_for_events()

    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({ mock_device.id, zigbee_test_utils.build_bind_request(mock_device,
      zigbee_test_utils.mock_hub_eui,
      PowerConfiguration.ID) })
    test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining
        :configure_reporting(mock_device,
          600,
          21600,
          1) })
    test.socket.zigbee:__expect_send({ mock_device.id, zigbee_test_utils.build_bind_request(mock_device,
      zigbee_test_utils.mock_hub_eui,
      DoorLock.ID) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:configure_reporting(mock_device,
      0,
      3600,
      0) })
    test.socket.zigbee:__expect_send({ mock_device.id, zigbee_test_utils.build_bind_request(mock_device,
      zigbee_test_utils.mock_hub_eui,
      Alarm.ID) })
    test.socket.zigbee:__expect_send({ mock_device.id, Alarm.attributes.AlarmCount:configure_reporting(mock_device,
      0,
      21600,
      0) })

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()

    test.mock_time.advance_time(2)
    expect_reload_all_codes_messages()
  end
)

test.register_coroutine_test(
  "Adding a credential should succeed and report users, credentials, and command result.",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(4, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 0, "guest", "pin", "1234" } } })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetPINCode(mock_device,
          1,
          DoorLockUserStatus.OCCUPIED_ENABLED,
          DoorLockUserType.UNRESTRICTED,
          "1234"
        )
      }
    )
    test.wait_for_events()

    test.mock_time.advance_time(4)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.GetPINCode(mock_device, 1)
      }
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
          mock_device,
          0x01,
          DoorLockUserStatus.OCCUPIED_ENABLED,
          DoorLockUserType.UNRESTRICTED,
          "1234"
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users({ { userIndex = 1, userName = "Guest1", userType = "guest" } },
          { state_change = true, visibility = { displayed = true } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({ { credentialIndex = 1, credentialType = "pin", userIndex = 1 } },
          { state_change = true, visibility = { displayed = true } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", credentialIndex = 1, userIndex = 1 },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
  end,
  {
    test_init = function()
      test_init_add_device()
    end
  }
)

test.register_coroutine_test(
  "Updating a credential should succeed and report users, credentials, and command result.",
  function()
    -- add credential first
    test.timer.__create_and_queue_test_time_advance_timer(4, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 0, "guest", "pin", "1234" } } })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetPINCode(mock_device,
          1,
          DoorLockUserStatus.OCCUPIED_ENABLED,
          DoorLockUserType.UNRESTRICTED,
          "1234"
        )
      }
    )
    test.wait_for_events()

    test.mock_time.advance_time(4)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.GetPINCode(mock_device, 1)
      }
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
          mock_device,
          0x01,
          DoorLockUserStatus.OCCUPIED_ENABLED,
          DoorLockUserType.UNRESTRICTED,
          "1234"
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users({ { userIndex = 1, userName = "Guest1", userType = "guest" } },
          { state_change = true, visibility = { displayed = true } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({ { credentialIndex = 1, credentialType = "pin", userIndex = 1 } },
          { state_change = true, visibility = { displayed = true } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", credentialIndex = 1, userIndex = 1 },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )

    test.timer.__create_and_queue_test_time_advance_timer(4, "oneshot")
    test.mock_time.advance_time(4)
    test.wait_for_events()

    -- update the credential
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockCredentials.ID,
        command = "updateCredential",
        args = { "1", "1", "pin", "changedPin123" }
      },
    })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetPINCode(mock_device,
          1,
          DoorLockUserStatus.OCCUPIED_ENABLED,
          DoorLockUserType.UNRESTRICTED,
          "changedPin123"
        )
      }
    )
    test.timer.__create_and_queue_test_time_advance_timer(4, "oneshot")
    test.mock_time.advance_time(4)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.GetPINCode(mock_device, 1)
      }
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
          mock_device,
          0x01,
          DoorLockUserStatus.OCCUPIED_ENABLED,
          DoorLockUserType.UNRESTRICTED,
          "abc123"
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {
            { userIndex = 1, userType = "guest", userName = "Guest1" }
          },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials(
          {
            { userIndex = 1, credentialIndex = 1, credentialType = "pin" }
          },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "updateCredential", statusCode = "success", credentialIndex = 1, userIndex = 1 },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.wait_for_events()
  end,
  {
    test_init = function()
      test_init_add_device()
    end
  }
)

test.register_message_test(
  "The lock reporting a single code has been set and then deleted should be handled",
  {
    -- add credential
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        DoorLock.client.commands.ProgrammingEventNotification.build_test_rx(
          mock_device,
          0x0,
          ProgrammingEventCode.PIN_CODE_ADDED,
          1,
          "1234",
          DoorLockUserType.UNRESTRICTED,
          DoorLockUserStatus.OCCUPIED_ENABLED,
          0x0000,
          "data"
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.lockUsers.users({ { userIndex = 1, userName = "Guest1", userType = "guest" } },
          { state_change = true, visibility = { displayed = true } }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials({ { credentialIndex = 1, credentialType = "pin", userIndex = 1 } },
          { state_change = true, visibility = { displayed = true } }))
    },

    -- delete the credential
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        DoorLock.client.commands.ProgrammingEventNotification.build_test_rx(
          mock_device,
          0x0,
          ProgrammingEventCode.PIN_CODE_DELETED,
          1,
          "1234",
          DoorLockUserType.UNRESTRICTED,
          DoorLockUserStatus.AVAILABLE,
          0x0000,
          "data"
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.lockUsers.users({},
          { state_change = true, visibility = { displayed = true } }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials({},
          { state_change = true, visibility = { displayed = true } }))
    }
  },
  { test_init = test_init_add_device }
)

test.register_message_test(
  "The lock reporting master code changed",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        DoorLock.client.commands.ProgrammingEventNotification.build_test_rx(
          mock_device,
          0x0,
          ProgrammingEventCode.MASTER_CODE_CHANGED
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult({ commandName = "updateCredential", statusCode = "success" },
          { state_change = true, visibility = { displayed = false } }))
    }
  }
)

test.register_message_test(
  "The lock reporting all codes have been deleted should be handled",
  {
    -- add a credential
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        DoorLock.client.commands.ProgrammingEventNotification.build_test_rx(
          mock_device,
          0x0,
          ProgrammingEventCode.PIN_CODE_ADDED,
          1,
          "1234",
          DoorLockUserType.UNRESTRICTED,
          DoorLockUserStatus.OCCUPIED_ENABLED,
          0x0000,
          "data"
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.lockUsers.users({ { userIndex = 1, userName = "Guest1", userType = "guest" } },
          { state_change = true, visibility = { displayed = true } }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials({ { credentialIndex = 1, credentialType = "pin", userIndex = 1 } },
          { state_change = true, visibility = { displayed = true } }))
    },

    -- delete all credentials
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        DoorLock.client.commands.ProgrammingEventNotification.build_test_rx(
          mock_device,
          0x0,
          ProgrammingEventCode.PIN_CODE_DELETED,
          0xFFFF
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.lockUsers.users({},
          { state_change = true, visibility = { displayed = true } }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials({},
          { state_change = true, visibility = { displayed = true } }))
    }
  },
  { test_init = test_init_add_device }
)

test.register_coroutine_test(
  "Out of band get pin call should add credential if it doesn't exist (happens during reload all codes).",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
          mock_device,
          0x01,
          DoorLockUserStatus.OCCUPIED_ENABLED,
          DoorLockUserType.UNRESTRICTED,
          "1234"
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users({ { userIndex = 1, userName = "Guest1", userType = "guest" } },
          { state_change = true, visibility = { displayed = true } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({ { credentialIndex = 1, credentialType = "pin", userIndex = 1 } },
          { state_change = true, visibility = { displayed = true } })
      )
    )
  end,
  {
    test_init = function()
      test_init_add_device()
    end
  }
)

test.run_registered_tests()
