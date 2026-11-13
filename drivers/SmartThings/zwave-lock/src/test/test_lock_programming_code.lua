-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Integration tests for the Yale programming code, which is kept in user code slot 251:
--   it is recorded by the code sync (or when the lock reports it), it is exposed as a programmingUser user whose
--   index matches the slot, it can be updated but not added or deleted, and delete-all keeps it. User identifier
--   0 (all users) is never sent for a single credential.

local test              = require "integration_test"
local t_utils           = require "integration_test.utils"
local capabilities      = require "st.capabilities"
local json              = require "st.json"
local zw                = require "st.zwave"
local constants         = require "lock_utils.constants"
local Notification      = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local UserCode          = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
local UserCodeV2        = (require "st.zwave.CommandClass.UserCode")({ version = 2 })
local Alarm             = (require "st.zwave.CommandClass.Alarm")({ version = 1 })
local access_control_event = Notification.event.access_control

test.disable_startup_messages()

local zwave_lock_endpoints = {
  {
    command_classes = {
      { value = zw.BATTERY },
      { value = zw.DOOR_LOCK },
      { value = zw.USER_CODE },
      { value = zw.NOTIFICATION },
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("base-lock.yml"),
  zwave_endpoints = zwave_lock_endpoints,
})

local yale_mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("base-lock.yml"),
  zwave_endpoints = zwave_lock_endpoints,
  zwave_manufacturer_id = 0x0129,
  zwave_product_type = 0x0002,
  zwave_product_id = 0x0000,
})

-- Capability state is reset for every test: get_latest_state only returns what the test seeded or the driver
-- emitted since, and the tables otherwise come from the persistent store.
local mock_latest_state = {}
local function mock_state_key(capability_id, attribute_name)
  return capability_id .. "|" .. attribute_name
end

local function install_state_mocks(device)
  mock_latest_state = {}
  device.get_latest_state = function(_, _, capability_id, attribute_name, default_value)
    local value = mock_latest_state[mock_state_key(capability_id, attribute_name)]
    if value == nil then return default_value end
    return value
  end
  device.emit_event = function(_, event)
    mock_latest_state[mock_state_key(event.capability.ID, event.attribute.NAME)] = event.value.value
    local message = device:generate_test_message("main", event)
    test.socket.capability:send(message[1], json.encode(message[2]))
  end
end

local function make_test_init(device)
  return function()
    install_state_mocks(device)
    device:set_field("persistedUsers", nil, { persist = true })
    device:set_field("persistedCredentials", nil, { persist = true })
    device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })
    test.mock_device.add_test_device(device)
  end
end

local function seed(device, users, credentials)
  mock_latest_state[mock_state_key(capabilities.lockUsers.ID, capabilities.lockUsers.users.NAME)] = users
  mock_latest_state[mock_state_key(capabilities.lockCredentials.ID, capabilities.lockCredentials.credentials.NAME)] = credentials
  device:set_field("persistedUsers", users, { persist = true })
  device:set_field("persistedCredentials", credentials, { persist = true })
end

local function expect_users(device, users)
  test.socket.capability:__expect_send(device:generate_test_message("main",
    capabilities.lockUsers.users(users, { visibility = { displayed = false } })))
end

local function expect_credentials(device, credentials)
  test.socket.capability:__expect_send(device:generate_test_message("main",
    capabilities.lockCredentials.credentials(credentials, { visibility = { displayed = false } })))
end

local function expect_credential_result(device, result)
  test.socket.capability:__expect_send(device:generate_test_message("main",
    capabilities.lockCredentials.commandResult(result, { state_change = true, visibility = { displayed = false } })))
end

local function queue_programming_code_changed(device)
  test.socket.zwave:__queue_receive({ device.id, Notification:Report({
    notification_type = Notification.notification_type.ACCESS_CONTROL,
    event = access_control_event.NEW_PROGRAM_CODE_ENTERED_UNIQUE_CODE_FOR_LOCK_CONFIGURATION,
  }) })
end

local PROGRAMMING_USER_ENTRY = { userIndex = 251, userName = "Programming Code", userType = "programmingUser" }
local PROGRAMMING_CREDENTIAL = { userIndex = 251, credentialIndex = 251, credentialType = "pin", credentialName = "Programming Code" }
local GUEST_USER = { userIndex = 1, userName = "Guest 1", userType = "guest" }
local GUEST_CREDENTIAL = { userIndex = 1, credentialIndex = 1, credentialType = "pin" }

-- ============================================================================
-- updating the programming code
-- ============================================================================

test.register_coroutine_test(
  "addCredential: user 251 is an ordinary user on a lock that is not a Yale",
  function()
    -- the credential takes the next free slot, not the programming code slot
    seed(mock_device, { { userIndex = 251, userName = "Guest 251", userType = "guest" } }, {})
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 251, "guest", "pin", "1234" } } })
    test.socket.zwave:__expect_send(UserCode:Set({
      user_identifier = 1,
      user_code = "1234",
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
    }):build_test_tx(mock_device.id))
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "updateCredential: Yale programming code is written to slot 251 and succeeds when the lock reports it changed",
  function()
    seed(yale_mock_device, { PROGRAMMING_USER_ENTRY }, { PROGRAMMING_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential", args = { 251, 251, "pin", "5678" } } })
    test.socket.zwave:__expect_send(UserCode:Set({
      user_identifier = 251,
      user_code = "5678",
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
    }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()

    queue_programming_code_changed(yale_mock_device)
    expect_credential_result(yale_mock_device, { commandName = "updateCredential", statusCode = "success" })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "updateCredential: Yale programming code update succeeds when the lock confirms it with a new user code event",
  function()
    seed(yale_mock_device, { PROGRAMMING_USER_ENTRY }, { PROGRAMMING_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential", args = { 251, 251, "pin", "5678" } } })
    test.socket.zwave:__expect_send(UserCode:Set({
      user_identifier = 251,
      user_code = "5678",
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
    }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()

    test.socket.zwave:__queue_receive({ yale_mock_device.id, Notification:Report({
      notification_type = Notification.notification_type.ACCESS_CONTROL,
      event = access_control_event.NEW_USER_CODE_ADDED,
      event_parameter = string.char(251),
    }) })
    expect_credential_result(yale_mock_device,
      { commandName = "updateCredential", statusCode = "success", userIndex = 251, credentialIndex = 251 })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "updateCredential: a programming code report during a guest update records the programming code and leaves the update alone",
  function()
    seed(yale_mock_device, { GUEST_USER }, { GUEST_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential", args = { 1, 1, "pin", "5678" } } })
    test.socket.zwave:__expect_send(UserCode:Set({
      user_identifier = 1,
      user_code = "5678",
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
    }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()

    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCode:Report({
      user_identifier = 251,
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
      user_code = "1234",
    }) })
    expect_users(yale_mock_device, { GUEST_USER, PROGRAMMING_USER_ENTRY })
    expect_credentials(yale_mock_device, { GUEST_CREDENTIAL, PROGRAMMING_CREDENTIAL })
    test.wait_for_events()

    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCode:Report({
      user_identifier = 1,
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
      user_code = "5678",
    }) })
    expect_credential_result(yale_mock_device,
      { commandName = "updateCredential", statusCode = "success", userIndex = 1, credentialIndex = 1 })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "the User Code v2 Master Code Report that follows a programming code change is ignored",
  function()
    seed(yale_mock_device, { PROGRAMMING_USER_ENTRY }, { PROGRAMMING_CREDENTIAL })
    queue_programming_code_changed(yale_mock_device)
    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCodeV2:MasterCodeReport({ master_code = "199111" }) })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

-- ============================================================================
-- the programming code cannot be deleted
-- ============================================================================

test.register_coroutine_test(
  "deleteCredential: the programming code cannot be deleted and nothing is sent to the lock",
  function()
    seed(yale_mock_device, { PROGRAMMING_USER_ENTRY }, { PROGRAMMING_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential", args = { 251, "pin" } } })
    expect_credential_result(yale_mock_device, { commandName = "deleteCredential", statusCode = "failure" })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "deleteUser: the programming code user cannot be deleted and fails for both capabilities",
  function()
    seed(yale_mock_device, { PROGRAMMING_USER_ENTRY }, { PROGRAMMING_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "deleteUser", args = { 251 } } })
    test.socket.capability:__expect_send(yale_mock_device:generate_test_message("main",
      capabilities.lockUsers.commandResult({ commandName = "deleteUser", statusCode = "failure" },
        { state_change = true, visibility = { displayed = false } })))
    expect_credential_result(yale_mock_device, { commandName = "deleteCredential", statusCode = "failure" })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "all user codes deleted at the lock keeps the Yale programming code",
  function()
    seed(yale_mock_device, { PROGRAMMING_USER_ENTRY, GUEST_USER }, { PROGRAMMING_CREDENTIAL, GUEST_CREDENTIAL })
    test.socket.zwave:__queue_receive({ yale_mock_device.id, Notification:Report({
      notification_type = Notification.notification_type.ACCESS_CONTROL,
      event = access_control_event.ALL_USER_CODES_DELETED,
    }) })
    expect_credentials(yale_mock_device, { PROGRAMMING_CREDENTIAL })
    expect_users(yale_mock_device, { PROGRAMMING_USER_ENTRY })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "an Alarm v1 all codes deleted report keeps the Yale programming code",
  function()
    seed(yale_mock_device, { PROGRAMMING_USER_ENTRY, GUEST_USER }, { PROGRAMMING_CREDENTIAL, GUEST_CREDENTIAL })
    test.socket.zwave:__queue_receive({ yale_mock_device.id, Alarm:Report({ alarm_type = 32 }) })
    expect_credentials(yale_mock_device, { PROGRAMMING_CREDENTIAL })
    expect_users(yale_mock_device, { PROGRAMMING_USER_ENTRY })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "addCredential: a programmingUser credential in a user slot counts toward the credential limit",
  function()
    local users, credentials = {}, {}
    for i = 1, 20 do
      table.insert(users, { userIndex = i, userName = "User " .. i, userType = i == 1 and "programmingUser" or "guest" })
      table.insert(credentials, { userIndex = i, credentialIndex = i, credentialType = "pin" })
    end
    seed(mock_device, users, credentials)
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 0, "guest", "pin", "1234" } } })
    expect_credential_result(mock_device, { commandName = "addCredential", statusCode = "resourceExhausted" })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(mock_device),
    min_api_version = 15
  }
)

-- ============================================================================
-- user identifier 0 means "all users" and is never used for a single credential
-- ============================================================================

test.register_coroutine_test(
  "updateCredential: credentialIndex 0 is rejected without sending user identifier 0",
  function()
    seed(mock_device, { GUEST_USER }, { GUEST_CREDENTIAL })
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential", args = { 1, 0, "pin", "5678" } } })
    expect_credential_result(mock_device, { commandName = "updateCredential", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "deleteCredential: credentialIndex 0 is rejected without sending user identifier 0",
  function()
    seed(mock_device, { GUEST_USER }, { GUEST_CREDENTIAL })
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential", args = { 0, "pin" } } })
    expect_credential_result(mock_device, { commandName = "deleteCredential", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "deleteAllCredentials: sends a single user identifier 0 clear and keeps the programming code in state",
  function()
    seed(yale_mock_device, { PROGRAMMING_USER_ENTRY, GUEST_USER }, { PROGRAMMING_CREDENTIAL, GUEST_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteAllCredentials", args = {} } })
    test.timer.__create_and_queue_test_time_advance_timer(4, "oneshot")
    test.socket.zwave:__expect_send(UserCode:Set({
      user_identifier = 0,
      user_id_status = UserCode.user_id_status.AVAILABLE,
    }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()

    test.mock_time.advance_time(4)
    expect_credentials(yale_mock_device, { PROGRAMMING_CREDENTIAL })
    expect_credential_result(yale_mock_device, { commandName = "deleteAllCredentials", statusCode = "success" })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

-- ============================================================================
-- programming code confirmed or reported in other ways
-- ============================================================================

local function queue_new_user_code_added(device, slot)
  test.socket.zwave:__queue_receive({ device.id, Notification:Report({
    notification_type = Notification.notification_type.ACCESS_CONTROL,
    event = access_control_event.NEW_USER_CODE_ADDED,
    event_parameter = string.char(slot),
  }) })
end

test.register_coroutine_test(
  "an out-of-band user code added event for index 0 is ignored",
  function()
    -- nothing is added or emitted
    queue_new_user_code_added(mock_device, 0)
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "new user code event at the Yale programming code slot with no command in progress adds the programming code",
  function()
    queue_new_user_code_added(yale_mock_device, 251)
    expect_users(yale_mock_device, { PROGRAMMING_USER_ENTRY })
    expect_credentials(yale_mock_device, { PROGRAMMING_CREDENTIAL })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "programming code report during an addCredential for another slot records the programming code and leaves the add alone",
  function()
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 0, "guest", "pin", "5555" } } })
    test.socket.zwave:__expect_send(UserCode:Set({
      user_identifier = 1,
      user_code = "5555",
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
    }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()

    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCode:Report({
      user_identifier = 251,
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
      user_code = "1234",
    }) })
    expect_users(yale_mock_device, { PROGRAMMING_USER_ENTRY })
    expect_credentials(yale_mock_device, { PROGRAMMING_CREDENTIAL })
    test.wait_for_events()

    -- the guest add still completes when the lock confirms it
    queue_new_user_code_added(yale_mock_device, 1)
    expect_credentials(yale_mock_device, { PROGRAMMING_CREDENTIAL,
      { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1" } })
    expect_users(yale_mock_device, { PROGRAMMING_USER_ENTRY, { userIndex = 1, userName = "Guest 1", userType = "guest" } })
    expect_credential_result(yale_mock_device,
      { commandName = "addCredential", statusCode = "success", userIndex = 1, credentialIndex = 1 })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

local function start_sync(device, code_index)
  device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
  device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.SYNC.CODES_FROM_LOCK, {})
  device:set_field(constants.SYNC.CODE_INDEX, code_index, {})
end

test.register_coroutine_test(
  "a programming code report during a sync records the programming code and the sync waits for the slot it asked for",
  function()
    start_sync(yale_mock_device, 2)
    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCode:Report({
      user_identifier = 251,
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
      user_code = "199111",
    }) })
    expect_users(yale_mock_device, { PROGRAMMING_USER_ENTRY })
    expect_credentials(yale_mock_device, { PROGRAMMING_CREDENTIAL })
    test.wait_for_events()

    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCode:Report({
      user_identifier = 2,
      user_id_status = UserCode.user_id_status.AVAILABLE,
    }) })
    test.socket.zwave:__expect_send(UserCode:Get({ user_identifier = 3 }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "an empty programming code slot report during a sync does not move the sync on",
  function()
    start_sync(yale_mock_device, 2)
    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCode:Report({
      user_identifier = 251,
      user_id_status = UserCode.user_id_status.AVAILABLE,
    }) })
    test.wait_for_events()

    -- the sync still waits for the index it asked for
    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCode:Report({
      user_identifier = 2,
      user_id_status = UserCode.user_id_status.AVAILABLE,
    }) })
    test.socket.zwave:__expect_send(UserCode:Get({ user_identifier = 3 }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "a sync that reaches the programming code slot records the programming code and moves on",
  function()
    -- a lock with more user slots than the programming code slot
    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCode:UsersNumberReport({ supported_users = 255 }) })
    test.socket.capability:__expect_send(yale_mock_device:generate_test_message("main",
      capabilities.lockUsers.totalUsersSupported(255, { state_change = true, visibility = { displayed = false } })))
    test.socket.capability:__expect_send(yale_mock_device:generate_test_message("main",
      capabilities.lockCredentials.pinUsersSupported(255, { state_change = true, visibility = { displayed = false } })))
    test.wait_for_events()

    start_sync(yale_mock_device, 251)
    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCode:Report({
      user_identifier = 251,
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
      user_code = "199111",
    }) })
    expect_users(yale_mock_device, { PROGRAMMING_USER_ENTRY })
    expect_credentials(yale_mock_device, { PROGRAMMING_CREDENTIAL })
    test.socket.zwave:__expect_send(UserCode:Get({ user_identifier = 252 }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "a new user code event at the programming code slot during a sync records the programming code, not a guest",
  function()
    start_sync(yale_mock_device, 2)
    queue_new_user_code_added(yale_mock_device, 251)
    expect_users(yale_mock_device, { PROGRAMMING_USER_ENTRY })
    expect_credentials(yale_mock_device, { PROGRAMMING_CREDENTIAL })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

-- ============================================================================
-- updating the programming code user
-- ============================================================================

local function expect_user_result(device, result)
  test.socket.capability:__expect_send(device:generate_test_message("main",
    capabilities.lockUsers.commandResult(result, { state_change = true, visibility = { displayed = false } })))
end

test.register_coroutine_test(
  "addUser: a Yale programming code user cannot be added in a user slot",
  function()
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "addUser", args = { "Owner", "programmingUser" } } })
    expect_user_result(yale_mock_device, { commandName = "addUser", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "addUser: other users can still be added on a Yale",
  function()
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "addUser", args = { "Guest", "guest" } } })
    expect_users(yale_mock_device, { { userIndex = 1, userName = "Guest", userType = "guest" } })
    expect_user_result(yale_mock_device, { commandName = "addUser", statusCode = "success", userIndex = 1 })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "updateUser: a guest cannot be made the programming code user",
  function()
    seed(yale_mock_device, { PROGRAMMING_USER_ENTRY, GUEST_USER }, { PROGRAMMING_CREDENTIAL, GUEST_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "updateUser",
        args = { 1, "Guest", "programmingUser" } } })
    expect_user_result(yale_mock_device, { commandName = "updateUser", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "updateUser: the programming code user cannot be changed to another type",
  function()
    seed(yale_mock_device, { PROGRAMMING_USER_ENTRY, GUEST_USER }, { PROGRAMMING_CREDENTIAL, GUEST_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "updateUser",
        args = { 251, "Master Code", "guest" } } })
    expect_user_result(yale_mock_device, { commandName = "updateUser", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "updateUser: the programming code user can be renamed and keeps its type",
  function()
    seed(yale_mock_device, { PROGRAMMING_USER_ENTRY }, { PROGRAMMING_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "updateUser",
        args = { 251, "Renamed Master", "programmingUser" } } })
    expect_users(yale_mock_device, { { userIndex = 251, userName = "Renamed Master", userType = "programmingUser" } })
    expect_user_result(yale_mock_device, { commandName = "updateUser", statusCode = "success", userIndex = 251 })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(yale_mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "updateUser: no lock can make a guest a programming user",
  function()
    seed(mock_device, { GUEST_USER }, { GUEST_CREDENTIAL })
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "updateUser",
        args = { 1, "Guest", "programmingUser" } } })
    expect_user_result(mock_device, { commandName = "updateUser", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "addUser: no lock can add a programming user",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "addUser", args = { "Owner", "programmingUser" } } })
    expect_user_result(mock_device, { commandName = "addUser", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "addCredential: no lock can add a credential of the programming user type",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 0, "programmingUser", "pin", "123456" } } })
    expect_credential_result(mock_device, { commandName = "addCredential", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(mock_device),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "addCredential: an existing programming user cannot be given another credential",
  function()
    seed(mock_device, { PROGRAMMING_USER_ENTRY }, {})
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 251, "guest", "pin", "123456" } } })
    expect_credential_result(mock_device, { commandName = "addCredential", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  {
    test_init = make_test_init(mock_device),
    min_api_version = 15
  }
)

test.run_registered_tests()
