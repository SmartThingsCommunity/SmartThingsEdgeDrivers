-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Integration tests for the Yale admin code, which is kept in user code slot 251:
--   it is set with a plain User Code Set and confirmed by the "master code changed" notification,
--   it is exposed as a programmingUser user whose index matches the slot, a delete is left to the lock and
--   reported as it confirms or refuses it, and delete-all keeps it. User identifier 0 (all users) is never
--   sent for a single credential.

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

local function queue_admin_code_changed(device)
  test.socket.zwave:__queue_receive({ device.id, Notification:Report({
    notification_type = Notification.notification_type.ACCESS_CONTROL,
    event = access_control_event.NEW_PROGRAM_CODE_ENTERED_UNIQUE_CODE_FOR_LOCK_CONFIGURATION,
  }) })
end

local ADMIN_USER = { userIndex = 251, userName = "Master Code", userType = "programmingUser" }
local ADMIN_CREDENTIAL = { userIndex = 251, credentialIndex = 251, credentialType = "pin", credentialName = "Master Code" }
local GUEST_USER = { userIndex = 1, userName = "Guest 1", userType = "guest" }
local GUEST_CREDENTIAL = { userIndex = 1, credentialIndex = 1, credentialType = "pin" }

-- ============================================================================
-- setting the admin code
-- ============================================================================

test.register_coroutine_test(
  "addCredential: Yale admin code is written to slot 251 and added when the lock reports it changed",
  function()
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 251, "programmingUser", "pin", "199111" } } })
    test.socket.zwave:__expect_send(UserCode:Set({
      user_identifier = 251,
      user_code = "199111",
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
    }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()

    -- The lock reports the change with a notification, not a User Code Report.
    queue_admin_code_changed(yale_mock_device)
    expect_users(yale_mock_device, { ADMIN_USER })
    expect_credentials(yale_mock_device, { ADMIN_CREDENTIAL })
    expect_credential_result(yale_mock_device,
      { commandName = "addCredential", statusCode = "success", userIndex = 251, credentialIndex = 251 })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "addCredential: a guest credential cannot be written to the Yale admin code slot",
  function()
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 251, "guest", "pin", "1234" } } })
    expect_credential_result(yale_mock_device, { commandName = "addCredential", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "addCredential: an existing Yale admin code is not overwritten and the add is reported as occupied",
  function()
    seed(yale_mock_device, { ADMIN_USER }, { ADMIN_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 251, "programmingUser", "pin", "9999" } } })
    expect_credential_result(yale_mock_device, { commandName = "addCredential", statusCode = "occupied" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "addCredential: user 251 is an ordinary user on a lock that is not a Yale",
  function()
    -- the credential takes the next free slot, not the admin code slot
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
  { test_init = make_test_init(mock_device) }
)

test.register_coroutine_test(
  "addCredential: the Yale admin code can be added when the credentials table is full",
  function()
    local function guests()
      local users, credentials = {}, {}
      for i = 1, 20 do
        table.insert(users, { userIndex = i, userName = "Guest " .. i, userType = "guest" })
        table.insert(credentials, { userIndex = i, credentialIndex = i, credentialType = "pin" })
      end
      return users, credentials
    end
    seed(yale_mock_device, guests())

    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 251, "programmingUser", "pin", "199111" } } })
    test.socket.zwave:__expect_send(UserCode:Set({
      user_identifier = 251,
      user_code = "199111",
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
    }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()

    queue_admin_code_changed(yale_mock_device)
    local expected_users, expected_credentials = guests()
    table.insert(expected_users, ADMIN_USER)
    table.insert(expected_credentials, ADMIN_CREDENTIAL)
    expect_users(yale_mock_device, expected_users)
    expect_credentials(yale_mock_device, expected_credentials)
    expect_credential_result(yale_mock_device,
      { commandName = "addCredential", statusCode = "success", userIndex = 251, credentialIndex = 251 })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "updateCredential: Yale admin code is written to slot 251 and succeeds when the lock reports it changed",
  function()
    seed(yale_mock_device, { ADMIN_USER }, { ADMIN_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential", args = { 251, 251, "pin", "5678" } } })
    test.socket.zwave:__expect_send(UserCode:Set({
      user_identifier = 251,
      user_code = "5678",
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
    }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()

    queue_admin_code_changed(yale_mock_device)
    expect_credential_result(yale_mock_device, { commandName = "updateCredential", statusCode = "success" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "updateCredential: Yale admin code update succeeds when the lock confirms it with a new user code event",
  function()
    seed(yale_mock_device, { ADMIN_USER }, { ADMIN_CREDENTIAL })
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
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "updateCredential: an admin code report during a guest update records the admin code and leaves the update alone",
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
    expect_users(yale_mock_device, { GUEST_USER, ADMIN_USER })
    expect_credentials(yale_mock_device, { GUEST_CREDENTIAL, ADMIN_CREDENTIAL })
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
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "the User Code v2 Master Code Report that follows an admin code change is ignored",
  function()
    seed(yale_mock_device, { ADMIN_USER }, { ADMIN_CREDENTIAL })
    queue_admin_code_changed(yale_mock_device)
    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCodeV2:MasterCodeReport({ master_code = "199111" }) })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

-- ============================================================================
-- deleting the admin code: the lock decides, and the driver reports what it did
-- ============================================================================

local DELETE_CONFIRM_DELAY = constants.DELETE_CONFIRM_DELAY

local function expect_delete_set(device, slot)
  test.socket.zwave:__expect_send(UserCode:Set({
    user_identifier = slot,
    user_id_status = UserCode.user_id_status.AVAILABLE,
  }):build_test_tx(device.id))
end

local function queue_delete_credential(device, slot)
  test.socket.capability:__queue_receive({ device.id,
    { capability = capabilities.lockCredentials.ID, command = "deleteCredential", args = { slot, "pin" } } })
end

local function queue_delete_admin_credential(device)
  queue_delete_credential(device, 251)
end

local function read_back_after_delay(device, slot)
  test.mock_time.advance_time(DELETE_CONFIRM_DELAY)
  test.socket.zwave:__expect_send(UserCode:Get({ user_identifier = slot }):build_test_tx(device.id))
  test.wait_for_events()
end

test.register_coroutine_test(
  "deleteCredential: the Yale admin code is deleted when the lock confirms it",
  function()
    seed(yale_mock_device, { ADMIN_USER }, { ADMIN_CREDENTIAL })
    test.timer.__create_and_queue_test_time_advance_timer(DELETE_CONFIRM_DELAY, "oneshot")
    queue_delete_admin_credential(yale_mock_device)
    expect_delete_set(yale_mock_device, 251)
    test.wait_for_events()

    test.socket.zwave:__queue_receive({ yale_mock_device.id, Notification:Report({
      notification_type = Notification.notification_type.ACCESS_CONTROL,
      event = access_control_event.SINGLE_USER_CODE_DELETED,
      v1_alarm_level = 251,
    }) })
    expect_credentials(yale_mock_device, {})
    expect_credential_result(yale_mock_device,
      { commandName = "deleteCredential", statusCode = "success", userIndex = 251, credentialIndex = 251 })
    test.wait_for_events()

    -- the delete is already confirmed, so the slot is not read back
    test.mock_time.advance_time(DELETE_CONFIRM_DELAY)
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "deleteCredential: an unconfirmed delete is read back and succeeds when the slot is empty",
  function()
    seed(yale_mock_device, { ADMIN_USER }, { ADMIN_CREDENTIAL })
    test.timer.__create_and_queue_test_time_advance_timer(DELETE_CONFIRM_DELAY, "oneshot")
    queue_delete_admin_credential(yale_mock_device)
    expect_delete_set(yale_mock_device, 251)
    test.wait_for_events()
    read_back_after_delay(yale_mock_device, 251)

    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCode:Report({
      user_identifier = 251,
      user_id_status = UserCode.user_id_status.AVAILABLE,
    }) })
    expect_credentials(yale_mock_device, {})
    expect_credential_result(yale_mock_device,
      { commandName = "deleteCredential", statusCode = "success", userIndex = 251, credentialIndex = 251 })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "deleteCredential: a delete the lock refuses is reported as a failure and the admin code is kept",
  function()
    seed(yale_mock_device, { ADMIN_USER }, { ADMIN_CREDENTIAL })
    test.timer.__create_and_queue_test_time_advance_timer(DELETE_CONFIRM_DELAY, "oneshot")
    queue_delete_admin_credential(yale_mock_device)
    expect_delete_set(yale_mock_device, 251)
    test.wait_for_events()
    read_back_after_delay(yale_mock_device, 251)

    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCode:Report({
      user_identifier = 251,
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
      user_code = "199111",
    }) })
    expect_credential_result(yale_mock_device, { commandName = "deleteCredential", statusCode = "failure" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "deleteCredential: the read-back timer of an earlier delete does not fire during a later delete of the same slot",
  function()
    seed(mock_device, { GUEST_USER }, { GUEST_CREDENTIAL })
    test.timer.__create_and_queue_test_time_advance_timer(DELETE_CONFIRM_DELAY, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(DELETE_CONFIRM_DELAY, "oneshot")
    queue_delete_credential(mock_device, 1)
    expect_delete_set(mock_device, 1)
    test.wait_for_events()

    -- the first delete is confirmed right away
    test.socket.zwave:__queue_receive({ mock_device.id, Notification:Report({
      notification_type = Notification.notification_type.ACCESS_CONTROL,
      event = access_control_event.SINGLE_USER_CODE_DELETED,
      v1_alarm_level = 1,
    }) })
    expect_credentials(mock_device, {})
    expect_credential_result(mock_device,
      { commandName = "deleteCredential", statusCode = "success", userIndex = 1, credentialIndex = 1 })
    test.wait_for_events()

    -- the slot is set again at the lock and deleted again before the first timer would fire
    test.socket.zwave:__queue_receive({ mock_device.id, UserCode:Report({
      user_identifier = 1,
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
      user_code = "1234",
    }) })
    expect_credentials(mock_device,
      { { userIndex = 2, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 2" } })
    expect_users(mock_device, { GUEST_USER, { userIndex = 2, userName = "Guest 2", userType = "guest" } })
    test.wait_for_events()
    queue_delete_credential(mock_device, 1)
    expect_delete_set(mock_device, 1)
    test.wait_for_events()

    -- only the second delete reads the slot back
    read_back_after_delay(mock_device, 1)
  end,
  { test_init = make_test_init(mock_device) }
)

test.register_coroutine_test(
  "deleteUser: a delete of the admin code user the lock refuses fails for both capabilities",
  function()
    seed(yale_mock_device, { ADMIN_USER }, { ADMIN_CREDENTIAL })
    test.timer.__create_and_queue_test_time_advance_timer(DELETE_CONFIRM_DELAY, "oneshot")
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "deleteUser", args = { 251 } } })
    expect_delete_set(yale_mock_device, 251)
    test.wait_for_events()
    read_back_after_delay(yale_mock_device, 251)

    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCode:Report({
      user_identifier = 251,
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
      user_code = "199111",
    }) })
    test.socket.capability:__expect_send(yale_mock_device:generate_test_message("main",
      capabilities.lockUsers.commandResult({ commandName = "deleteUser", statusCode = "failure" },
        { state_change = true, visibility = { displayed = false } })))
    expect_credential_result(yale_mock_device, { commandName = "deleteCredential", statusCode = "failure" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "all user codes deleted at the lock keeps the Yale admin code",
  function()
    seed(yale_mock_device, { ADMIN_USER, GUEST_USER }, { ADMIN_CREDENTIAL, GUEST_CREDENTIAL })
    test.socket.zwave:__queue_receive({ yale_mock_device.id, Notification:Report({
      notification_type = Notification.notification_type.ACCESS_CONTROL,
      event = access_control_event.ALL_USER_CODES_DELETED,
    }) })
    expect_credentials(yale_mock_device, { ADMIN_CREDENTIAL })
    expect_users(yale_mock_device, { ADMIN_USER })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "an Alarm v1 all codes deleted report keeps the Yale admin code",
  function()
    seed(yale_mock_device, { ADMIN_USER, GUEST_USER }, { ADMIN_CREDENTIAL, GUEST_CREDENTIAL })
    test.socket.zwave:__queue_receive({ yale_mock_device.id, Alarm:Report({ alarm_type = 32 }) })
    expect_credentials(yale_mock_device, { ADMIN_CREDENTIAL })
    expect_users(yale_mock_device, { ADMIN_USER })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "all user codes deleted at a Yale keeps only the admin code, not a programmingUser in a user slot",
  function()
    local slot_user = { userIndex = 3, userName = "Slot 3", userType = "programmingUser" }
    local slot_credential = { userIndex = 3, credentialIndex = 3, credentialType = "pin" }
    seed(yale_mock_device, { slot_user, ADMIN_USER }, { slot_credential, ADMIN_CREDENTIAL })
    test.socket.zwave:__queue_receive({ yale_mock_device.id, Notification:Report({
      notification_type = Notification.notification_type.ACCESS_CONTROL,
      event = access_control_event.ALL_USER_CODES_DELETED,
    }) })
    expect_credentials(yale_mock_device, { ADMIN_CREDENTIAL })
    expect_users(yale_mock_device, { ADMIN_USER })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "all user codes deleted at a lock that is not a Yale clears a programmingUser user",
  function()
    seed(mock_device, { { userIndex = 1, userName = "Owner", userType = "programmingUser" } }, { GUEST_CREDENTIAL })
    test.socket.zwave:__queue_receive({ mock_device.id, Notification:Report({
      notification_type = Notification.notification_type.ACCESS_CONTROL,
      event = access_control_event.ALL_USER_CODES_DELETED,
    }) })
    expect_credentials(mock_device, {})
    expect_users(mock_device, {})
    test.wait_for_events()
  end,
  { test_init = make_test_init(mock_device) }
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
  { test_init = make_test_init(mock_device) }
)

-- ============================================================================
-- user identifier 0 means "all users" and is never used for a single credential
-- ============================================================================

test.register_coroutine_test(
  "updateCredential: credentialIndex 0 is rejected without sending user identifier 0",
  function()
    seed(mock_device, { { userIndex = 1, userName = "Master Code", userType = "guest" } },
         { { userIndex = 1, credentialIndex = 0, credentialType = "pin" } })
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential", args = { 1, 0, "pin", "5678" } } })
    expect_credential_result(mock_device, { commandName = "updateCredential", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(mock_device) }
)

test.register_coroutine_test(
  "deleteCredential: credentialIndex 0 is rejected without sending user identifier 0",
  function()
    seed(mock_device, { { userIndex = 1, userName = "Master Code", userType = "guest" } },
         { { userIndex = 1, credentialIndex = 0, credentialType = "pin" } })
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential", args = { 0, "pin" } } })
    expect_credential_result(mock_device, { commandName = "deleteCredential", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(mock_device) }
)

test.register_coroutine_test(
  "deleteUser: a stale credential at index 0 is removed locally without sending user identifier 0",
  function()
    seed(mock_device, { GUEST_USER }, { { userIndex = 1, credentialIndex = 0, credentialType = "pin" } })
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "deleteUser", args = { 1 } } })
    expect_users(mock_device, {})
    expect_credentials(mock_device, {})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockUsers.commandResult({ commandName = "deleteUser", statusCode = "success", userIndex = 1 },
        { state_change = true, visibility = { displayed = false } })))
    expect_credential_result(mock_device,
      { commandName = "deleteCredential", statusCode = "success", userIndex = 1, credentialIndex = 0 })
    test.wait_for_events()
  end,
  { test_init = make_test_init(mock_device) }
)

test.register_coroutine_test(
  "deleteAllCredentials: sends a single user identifier 0 clear and keeps the admin code in state",
  function()
    seed(yale_mock_device, { ADMIN_USER, GUEST_USER }, { ADMIN_CREDENTIAL, GUEST_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteAllCredentials", args = {} } })
    test.timer.__create_and_queue_test_time_advance_timer(4, "oneshot")
    test.socket.zwave:__expect_send(UserCode:Set({
      user_identifier = 0,
      user_id_status = UserCode.user_id_status.AVAILABLE,
    }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()

    test.mock_time.advance_time(4)
    expect_credentials(yale_mock_device, { ADMIN_CREDENTIAL })
    expect_credential_result(yale_mock_device, { commandName = "deleteAllCredentials", statusCode = "success" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

-- ============================================================================
-- admin code confirmed or reported in other ways
-- ============================================================================

local function queue_new_user_code_added(device, slot)
  test.socket.zwave:__queue_receive({ device.id, Notification:Report({
    notification_type = Notification.notification_type.ACCESS_CONTROL,
    event = access_control_event.NEW_USER_CODE_ADDED,
    event_parameter = string.char(slot),
  }) })
end

test.register_coroutine_test(
  "addCredential: Yale admin code is added when the lock confirms the write with a new user code event",
  function()
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 251, "programmingUser", "pin", "199111" } } })
    test.socket.zwave:__expect_send(UserCode:Set({
      user_identifier = 251,
      user_code = "199111",
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
    }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()

    queue_new_user_code_added(yale_mock_device, 251)
    expect_users(yale_mock_device, { ADMIN_USER })
    expect_credentials(yale_mock_device, { ADMIN_CREDENTIAL })
    expect_credential_result(yale_mock_device,
      { commandName = "addCredential", statusCode = "success", userIndex = 251, credentialIndex = 251 })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "new user code event at the Yale admin slot with no command in progress adds the admin code",
  function()
    queue_new_user_code_added(yale_mock_device, 251)
    expect_users(yale_mock_device, { ADMIN_USER })
    expect_credentials(yale_mock_device, { ADMIN_CREDENTIAL })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "admin code report during an addCredential for another slot records the admin code and leaves the add alone",
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
    expect_users(yale_mock_device, { ADMIN_USER })
    expect_credentials(yale_mock_device, { ADMIN_CREDENTIAL })
    test.wait_for_events()

    -- the guest add still completes when the lock confirms it
    queue_new_user_code_added(yale_mock_device, 1)
    expect_credentials(yale_mock_device, { ADMIN_CREDENTIAL,
      { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1" } })
    expect_users(yale_mock_device, { ADMIN_USER, { userIndex = 1, userName = "Guest 1", userType = "guest" } })
    expect_credential_result(yale_mock_device,
      { commandName = "addCredential", statusCode = "success", userIndex = 1, credentialIndex = 1 })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

local function start_sync(device, code_index)
  device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
  device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.SYNC.CODES_FROM_LOCK, {})
  device:set_field(constants.SYNC.CODE_INDEX, code_index, {})
end

test.register_coroutine_test(
  "an admin code report during a sync records the admin code and the sync waits for the slot it asked for",
  function()
    start_sync(yale_mock_device, 2)
    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCode:Report({
      user_identifier = 251,
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
      user_code = "199111",
    }) })
    expect_users(yale_mock_device, { ADMIN_USER })
    expect_credentials(yale_mock_device, { ADMIN_CREDENTIAL })
    test.wait_for_events()

    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCode:Report({
      user_identifier = 2,
      user_id_status = UserCode.user_id_status.AVAILABLE,
    }) })
    test.socket.zwave:__expect_send(UserCode:Get({ user_identifier = 3 }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "a sync that reaches the admin code slot records the admin code and moves on",
  function()
    -- a lock with more user slots than the admin code slot
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
    expect_users(yale_mock_device, { ADMIN_USER })
    expect_credentials(yale_mock_device, { ADMIN_CREDENTIAL })
    test.socket.zwave:__expect_send(UserCode:Get({ user_identifier = 252 }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "a new user code event at the admin slot during a sync records the admin code, not a guest",
  function()
    start_sync(yale_mock_device, 2)
    queue_new_user_code_added(yale_mock_device, 251)
    expect_users(yale_mock_device, { ADMIN_USER })
    expect_credentials(yale_mock_device, { ADMIN_CREDENTIAL })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

-- ============================================================================
-- updating the admin code user
-- ============================================================================

local function expect_user_result(device, result)
  test.socket.capability:__expect_send(device:generate_test_message("main",
    capabilities.lockUsers.commandResult(result, { state_change = true, visibility = { displayed = false } })))
end

test.register_coroutine_test(
  "addUser: a Yale admin code user cannot be added in a user slot",
  function()
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "addUser", args = { "Owner", "programmingUser" } } })
    expect_user_result(yale_mock_device, { commandName = "addUser", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
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
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "updateUser: a guest cannot be made the admin code user",
  function()
    seed(yale_mock_device, { ADMIN_USER, GUEST_USER }, { ADMIN_CREDENTIAL, GUEST_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "updateUser",
        args = { 1, "Guest", "programmingUser" } } })
    expect_user_result(yale_mock_device, { commandName = "updateUser", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "updateUser: the admin code user cannot be changed to another type",
  function()
    seed(yale_mock_device, { ADMIN_USER, GUEST_USER }, { ADMIN_CREDENTIAL, GUEST_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "updateUser",
        args = { 251, "Master Code", "guest" } } })
    expect_user_result(yale_mock_device, { commandName = "updateUser", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "updateUser: the admin code user can be renamed and keeps its type",
  function()
    seed(yale_mock_device, { ADMIN_USER }, { ADMIN_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "updateUser",
        args = { 251, "Renamed Master", "programmingUser" } } })
    expect_users(yale_mock_device, { { userIndex = 251, userName = "Renamed Master", userType = "programmingUser" } })
    expect_user_result(yale_mock_device, { commandName = "updateUser", statusCode = "success", userIndex = 251 })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "updateUser: other locks are not restricted by the admin code user type",
  function()
    seed(mock_device, { GUEST_USER }, { GUEST_CREDENTIAL })
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "updateUser",
        args = { 1, "Guest", "programmingUser" } } })
    expect_users(mock_device, { { userIndex = 1, userName = "Guest", userType = "programmingUser" } })
    expect_user_result(mock_device, { commandName = "updateUser", statusCode = "success", userIndex = 1 })
    test.wait_for_events()
  end,
  { test_init = make_test_init(mock_device) }
)

test.run_registered_tests()
