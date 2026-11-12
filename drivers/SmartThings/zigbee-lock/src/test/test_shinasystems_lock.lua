-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Integration tests for the ShinaSystem DLM-300Z sub-driver. The device is always handled with
-- lockUsers/lockCredentials, and its profile does not have the deprecated lockCodes. A newly joined
-- device is therefore migrated when it is added, and a device that was not migrated yet is
-- migrated by the init of the sub-driver.

local test              = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils           = require "integration_test.utils"

local capabilities       = require "st.capabilities"
local clusters           = require "st.zigbee.zcl.clusters"
local DoorLock           = clusters.DoorLock
local PowerConfiguration = clusters.PowerConfiguration
local Alarms             = clusters.Alarms
local constants          = require "lock_utils.constants"

local DoorState = DoorLock.attributes.DoorState

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("base-lock-door-state.yml"),
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "ShinaSystem",
      model = "DLM-300Z",
      server_clusters = { 0x0000, 0x0001, 0x0009, 0x0101 }
    }
  }
})

zigbee_test_utils.prepare_zigbee_env_info()

local function make_test_init(migrated)
  return function()
    test.disable_startup_messages()
    test.mock_device.add_test_device(mock_device)
    if migrated then
      mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })
    end
  end
end

test.set_test_init_function(make_test_init(true))

local function assert_migrated()
  assert(mock_device:get_field(constants.DRIVER_STATE.SLGA_MIGRATED) == true, "the device should be migrated")
end

-- the refresh of a device that has no PIN code length state yet. The number of PIN users is only
-- read as long as the init has not set it.
local function expect_refresh(pin_users_known)
  test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, Alarms.attributes.AlarmCount:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.MaxPINCodeLength:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.MinPINCodeLength:read(mock_device) })
  if not pin_users_known then
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:read(mock_device) })
  end
  test.socket.zigbee:__expect_send({ mock_device.id, DoorState:read(mock_device) })
end

-- the messages of every init: the default handler reads the number of PIN users as the profile has
-- no lockCodes, and the sub-driver reports the lock states and commands, the door states, the PIN
-- support and the single PIN of the DLM-300Z
local function expect_init_events()
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:read(mock_device) })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main",
      capabilities.lock.supportedLockValues({ "locked", "unlocked" }, { visibility = { displayed = false } }))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main",
      capabilities.lock.supportedLockCommands({ "lock", "unlock" }, { visibility = { displayed = false } }))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main",
      capabilities.doorState.supportedDoorStates({ "open", "closed" }, { visibility = { displayed = false } }))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main",
      capabilities.lockCredentials.supportedCredentials({ "pin" }, { visibility = { displayed = false } }))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lockCredentials.pinUsersSupported(1, { visibility = { displayed = false } }))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lockUsers.totalUsersSupported(1, { visibility = { displayed = false } }))
  )
end

local function expect_sync_device_state()
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.SendPINOverTheAir:write(mock_device, true) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.GetPINCode(mock_device, 1) })
end

local command_result_opts = { state_change = true, visibility = { displayed = false } }
local hidden = { visibility = { displayed = false } }

local function expect_users(users)
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockUsers.users(users, hidden)))
end

local function expect_credentials(credentials)
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lockCredentials.credentials(credentials, hidden))
  )
end

local function expect_command_result(capability, result)
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capability.commandResult(result, command_result_opts))
  )
end

-- the init sets the single PIN limit, then a PIN is added for a new user
local function init_and_add_pin()
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  expect_init_events()
  test.wait_for_events()

  test.socket.capability:__queue_receive({
    mock_device.id,
    { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 0, "guest", "pin", "1234" } },
  })
  test.socket.zigbee:__expect_send({
    mock_device.id,
    DoorLock.server.commands.SetPINCode(mock_device,
      1, DoorLock.types.DrlkUserStatus.OCCUPIED_ENABLED, DoorLock.types.DrlkUserType.UNRESTRICTED_USER, "1234"),
  })
  test.wait_for_events()

  test.socket.zigbee:__queue_receive({
    mock_device.id,
    DoorLock.client.commands.SetPINCodeResponse.build_test_rx(mock_device, DoorLock.types.DrlkSetCodeStatus.SUCCESS),
  })
  expect_users({ { userIndex = 1, userName = "Guest 1", userType = "guest" } })
  expect_credentials({ { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1" } })
  expect_command_result(capabilities.lockCredentials,
    { commandName = "addCredential", statusCode = "success", userIndex = 1, credentialIndex = 1 })
  test.wait_for_events()
end

local function expect_clear_pin()
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.SendPINOverTheAir:write(mock_device, true) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearPINCode(mock_device, 1) })
end

local function receive_clear_pin_response(status)
  test.socket.zigbee:__queue_receive({
    mock_device.id, DoorLock.client.commands.ClearPINCodeResponse.build_test_rx(mock_device, status)
  })
end

-- ============================================================================
-- DoorState attribute
-- ============================================================================

test.register_coroutine_test(
  "DoorState report should be handled as a doorState event",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, DoorState:build_test_attr_report(mock_device, DoorState.OPEN) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.doorState.open())
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, DoorState:build_test_attr_report(mock_device, DoorState.CLOSED) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.doorState.doorState.closed())
    )
    test.wait_for_events()

    -- error states are neither open nor closed, so no event is expected
    test.socket.zigbee:__queue_receive({ mock_device.id, DoorState:build_test_attr_report(mock_device, DoorState.ERROR_JAMMED) })
    test.wait_for_events()
  end
)

-- ============================================================================
-- refresh command
-- ============================================================================

test.register_coroutine_test(
  "Refresh should also read the DoorState",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} }
    })
    expect_refresh()
    test.wait_for_events()
  end
)

-- ============================================================================
-- doConfigure
-- ============================================================================

test.register_coroutine_test(
  "doConfigure should configure the DLM-300Z reporting, then sync the codes from the lock",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(15, "oneshot")
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID),
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 600, 21600, 1),
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, DoorLock.ID),
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.attributes.LockState:configure_reporting(mock_device, 0, 3600, 0),
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Alarms.ID),
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Alarms.attributes.AlarmCount:configure_reporting(mock_device, 0, 21600, 1),
    })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorState:configure_reporting(mock_device, 0, 3600) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.type("AA")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.quantity(4)))
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()

    test.mock_time.advance_time(15)
    expect_sync_device_state()
    test.wait_for_events()
  end
)

-- ============================================================================
-- migration to lockUsers/lockCredentials
-- ============================================================================

test.register_coroutine_test(
  "added: a newly joined device should be migrated, then refreshed by the default handler",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    expect_refresh()
    test.wait_for_events()

    assert_migrated()
  end,
  { test_init = make_test_init(false) }
)

test.register_coroutine_test(
  "init: a device that was onboarded before should be migrated, refreshed and have its codes synced",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(15, "oneshot")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
    expect_init_events()
    expect_refresh(true)
    test.wait_for_events()
    assert_migrated()

    test.mock_time.advance_time(15)
    expect_sync_device_state()
    test.wait_for_events()
  end,
  { test_init = make_test_init(false) }
)

test.register_coroutine_test(
  "init: a migrated device should only report what the DLM-300Z supports, and not be refreshed or synced again",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
    expect_init_events()
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "NumberOfPINUsersSupported should not switch the device to the base-lock profile",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.attributes.NumberOfPINUsersSupported:build_test_attr_report(mock_device, 1)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockCredentials.pinUsersSupported(1, { visibility = { displayed = false } }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockUsers.totalUsersSupported(1, { visibility = { displayed = false } }))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "A second credential should be refused, as the DLM-300Z accepts a SetPINCode for a slot it does not have",
  function()
    -- the number of PIN users is set by the init, without it having been read from the device
    init_and_add_pin()

    -- no SetPINCode is sent for a second credential
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 0, "guest", "pin", "5678" } },
    })
    expect_command_result(capabilities.lockCredentials,
      { commandName = "addCredential", statusCode = "resourceExhausted" })
    test.wait_for_events()
  end
)

-- ============================================================================
-- deleteAllCredentials / deleteAllUsers: the DLM-300Z does not support ClearAllPINCodes
-- ============================================================================

test.register_coroutine_test(
  "deleteAllCredentials should clear the single PIN instead of sending a ClearAllPINCodes, and delete its user",
  function()
    init_and_add_pin()

    test.socket.capability:__queue_receive({
      mock_device.id, { capability = capabilities.lockCredentials.ID, command = "deleteAllCredentials", args = {} }
    })
    expect_clear_pin()
    test.wait_for_events()

    receive_clear_pin_response(DoorLock.types.DrlkPassFailStatus.PASS)
    expect_users({})
    expect_credentials({})
    expect_command_result(capabilities.lockCredentials,
      { commandName = "deleteAllCredentials", statusCode = "success" })
    test.wait_for_events()

    -- the user slot is free again, so the next PIN is added for user 1
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 0, "guest", "pin", "5678" } },
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
        1, DoorLock.types.DrlkUserStatus.OCCUPIED_ENABLED, DoorLock.types.DrlkUserType.UNRESTRICTED_USER, "5678"),
    })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "deleteAllUsers should clear the single PIN, then report the result of both capabilities",
  function()
    init_and_add_pin()

    test.socket.capability:__queue_receive({
      mock_device.id, { capability = capabilities.lockUsers.ID, command = "deleteAllUsers", args = {} }
    })
    expect_clear_pin()
    test.wait_for_events()

    receive_clear_pin_response(DoorLock.types.DrlkPassFailStatus.PASS)
    expect_users({})
    expect_credentials({})
    expect_command_result(capabilities.lockUsers, { commandName = "deleteAllUsers", statusCode = "success" })
    expect_command_result(capabilities.lockCredentials,
      { commandName = "deleteAllCredentials", statusCode = "success" })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "deleteAllUsers should not send anything to the lock when there is no PIN to clear",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id, { capability = capabilities.lockUsers.ID, command = "addUser", args = { "Guest", "guest" } }
    })
    expect_users({ { userIndex = 1, userName = "Guest", userType = "guest" } })
    expect_command_result(capabilities.lockUsers, { commandName = "addUser", statusCode = "success", userIndex = 1 })
    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id, { capability = capabilities.lockUsers.ID, command = "deleteAllUsers", args = {} }
    })
    expect_users({})
    expect_credentials({})
    expect_command_result(capabilities.lockUsers, { commandName = "deleteAllUsers", statusCode = "success" })
    expect_command_result(capabilities.lockCredentials,
      { commandName = "deleteAllCredentials", statusCode = "success" })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "deleteAllCredentials should report a failure and keep the credential when the PIN is not cleared",
  function()
    init_and_add_pin()

    test.socket.capability:__queue_receive({
      mock_device.id, { capability = capabilities.lockCredentials.ID, command = "deleteAllCredentials", args = {} }
    })
    expect_clear_pin()
    test.wait_for_events()

    receive_clear_pin_response(DoorLock.types.DrlkPassFailStatus.FAIL)
    expect_command_result(capabilities.lockCredentials,
      { commandName = "deleteAllCredentials", statusCode = "failure" })
    test.wait_for_events()

    -- the credential is still there, so it is cleared again by the next command
    test.socket.capability:__queue_receive({
      mock_device.id, { capability = capabilities.lockCredentials.ID, command = "deleteAllCredentials", args = {} }
    })
    expect_clear_pin()
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "deleteAllCredentials should report busy while another command is in progress",
  function()
    -- the lock has not answered the SetPINCode yet
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 0, "guest", "pin", "1234" } },
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
        1, DoorLock.types.DrlkUserStatus.OCCUPIED_ENABLED, DoorLock.types.DrlkUserType.UNRESTRICTED_USER, "1234"),
    })
    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id, { capability = capabilities.lockCredentials.ID, command = "deleteAllCredentials", args = {} }
    })
    expect_command_result(capabilities.lockCredentials, { commandName = "deleteAllCredentials", statusCode = "busy" })
    test.wait_for_events()
  end
)

-- ============================================================================
-- ClearPINCodeResponse of a single credential: still handled by the default handler
-- ============================================================================

test.register_coroutine_test(
  "deleteCredential should still be handled by the default handler of the ClearPINCodeResponse",
  function()
    init_and_add_pin()

    test.socket.capability:__queue_receive({
      mock_device.id, { capability = capabilities.lockCredentials.ID, command = "deleteCredential", args = { 1, "pin" } }
    })
    expect_clear_pin()
    test.wait_for_events()

    receive_clear_pin_response(DoorLock.types.DrlkPassFailStatus.PASS)
    expect_credentials({})
    expect_users({})
    expect_command_result(capabilities.lockCredentials,
      { commandName = "deleteCredential", statusCode = "success", credentialIndex = 1, userIndex = 1 })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "deleteUser should still be handled by the default handler of the ClearPINCodeResponse",
  function()
    init_and_add_pin()

    -- deleteUser injects a deleteCredential for the PIN of the user
    test.socket.capability:__queue_receive({
      mock_device.id, { capability = capabilities.lockUsers.ID, command = "deleteUser", args = { 1 } }
    })
    expect_clear_pin()
    test.wait_for_events()

    receive_clear_pin_response(DoorLock.types.DrlkPassFailStatus.PASS)
    expect_credentials({})
    expect_users({})
    expect_command_result(capabilities.lockUsers, { commandName = "deleteUser", statusCode = "success", userIndex = 1 })
    expect_command_result(capabilities.lockCredentials,
      { commandName = "deleteCredential", statusCode = "success", credentialIndex = 1, userIndex = 1 })
    test.wait_for_events()
  end
)

test.run_registered_tests()
