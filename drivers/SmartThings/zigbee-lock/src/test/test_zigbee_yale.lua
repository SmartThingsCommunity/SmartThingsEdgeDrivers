-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Tests for the post-migration Yale subdriver: slot 255 handling and master code deletion.

local test              = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils           = require "integration_test.utils"
local capabilities      = require "st.capabilities"
local clusters          = require "st.zigbee.zcl.clusters"
local DoorLock          = clusters.DoorLock
local constants         = require "lock_utils.constants"

local DoorLockUserStatus = DoorLock.types.DrlkUserStatus
local DoorLockUserType   = DoorLock.types.DrlkUserType

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("base-lock.yml"),
  zigbee_endpoints = {
    [1] = { id = 1, manufacturer = "Yale", model = "YRD256", server_clusters = { DoorLock.ID } },
  },
})
zigbee_test_utils.prepare_zigbee_env_info()

local MASTER_USERS = { { userIndex = 1, userName = "Master Code", userType = "controlOnlyMember" } }
local MASTER_CREDENTIALS = { { userIndex = 1, credentialIndex = 0, credentialType = "pin", credentialName = "Master Code" } }

local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

local function expect_master_state()
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main",
      capabilities.lockCredentials.credentials(MASTER_CREDENTIALS, { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main",
      capabilities.lockUsers.users(MASTER_USERS, { visibility = { displayed = false } })))
end

test.register_coroutine_test(
  "GetPINCodeResponse for user id 0xFFEE is recorded as the slot 0 master code and sync continues",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.SYNC.CODES_FROM_LOCK, {})
    mock_device:set_field(constants.SYNC.CODE_INDEX, 0, {})

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
        mock_device, 0xFFEE, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.MASTER_USER, "1234"),
    })
    expect_master_state()
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.GetPINCode(mock_device, 1) })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "GetPINCodeResponse for slot 0 with a non-master user type is still recorded as the master code",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.SYNC.CODES_FROM_LOCK, {})
    mock_device:set_field(constants.SYNC.CODE_INDEX, 0, {})

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
        mock_device, 0xFFEE, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED_USER, "1234"),
    })
    expect_master_state()
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.GetPINCode(mock_device, 1) })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "deleteCredential(0) is ignored: no ClearPINCode is sent, the master code is kept, and a failure is reported",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
        mock_device, 0, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.MASTER_USER, "1234"),
    })
    expect_master_state()
    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential", args = { 0, "pin" } },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteCredential", statusCode = "failure" },
          { state_change = true, visibility = { displayed = false } })))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "deleteCredential for another slot still clears the PIN on a Yale lock",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
        mock_device, 3, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "1234"),
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 3, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } })))
    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential", args = { 3, "pin" } },
    })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.SendPINOverTheAir:write(mock_device, true) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearPINCode(mock_device, 3) })
    test.wait_for_events()
  end
)

test.run_registered_tests()
