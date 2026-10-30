-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Integration tests for the Yale master code, which is kept in user code slot 251:
--   it is set with a plain User Code Set and confirmed by the "master code changed" notification,
--   it is exposed as a controlOnlyMember user whose index matches the slot, and it is protected from
--   deletion and from delete-all. User identifier 0 (all users) is never sent for a single credential.

local test              = require "integration_test"
local t_utils           = require "integration_test.utils"
local capabilities      = require "st.capabilities"
local json              = require "st.json"
local zw                = require "st.zwave"
local constants         = require "lock_utils.constants"
local Notification      = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local UserCode          = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
local UserCodeV2        = (require "st.zwave.CommandClass.UserCode")({ version = 2 })
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
  zwave_manufacturer_id = constants.ADMIN.YALE_MANUFACTURER_ID,
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

local function queue_master_code_changed(device)
  test.socket.zwave:__queue_receive({ device.id, Notification:Report({
    notification_type = Notification.notification_type.ACCESS_CONTROL,
    event = access_control_event.NEW_PROGRAM_CODE_ENTERED_UNIQUE_CODE_FOR_LOCK_CONFIGURATION,
  }) })
end

local MASTER_USER = { userIndex = 251, userName = "Master Code", userType = "controlOnlyMember" }
local MASTER_CREDENTIAL = { userIndex = 251, credentialIndex = 251, credentialType = "pin", credentialName = "Master Code" }
local GUEST_USER = { userIndex = 1, userName = "Guest 1", userType = "guest" }
local GUEST_CREDENTIAL = { userIndex = 1, credentialIndex = 1, credentialType = "pin" }

-- ============================================================================
-- setting the master code
-- ============================================================================

test.register_coroutine_test(
  "addCredential: Yale master code is written to slot 251 and added when the lock reports it changed",
  function()
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 251, "controlOnlyMember", "pin", "199111" } } })
    test.socket.zwave:__expect_send(UserCode:Set({
      user_identifier = 251,
      user_code = "199111",
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
    }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()

    -- The lock reports the change with a notification, not a User Code Report.
    queue_master_code_changed(yale_mock_device)
    expect_users(yale_mock_device, { MASTER_USER })
    expect_credentials(yale_mock_device, { MASTER_CREDENTIAL })
    expect_credential_result(yale_mock_device,
      { commandName = "addCredential", statusCode = "success", userIndex = 251, credentialIndex = 251 })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "addCredential: a guest credential cannot be written to the Yale master code slot",
  function()
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 251, "guest", "pin", "1234" } } })
    expect_credential_result(yale_mock_device, { commandName = "addCredential", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "addCredential: slot 251 is an ordinary slot on a lock that is not a Yale",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 251, "guest", "pin", "1234" } } })
    test.socket.zwave:__expect_send(UserCode:Set({
      user_identifier = 251,
      user_code = "1234",
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
    }):build_test_tx(mock_device.id))
    test.wait_for_events()
  end,
  { test_init = make_test_init(mock_device) }
)

test.register_coroutine_test(
  "addCredential: the Yale master code can be added when the credentials table is full",
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
        args = { 251, "controlOnlyMember", "pin", "199111" } } })
    test.socket.zwave:__expect_send(UserCode:Set({
      user_identifier = 251,
      user_code = "199111",
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
    }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()

    queue_master_code_changed(yale_mock_device)
    local expected_users, expected_credentials = guests()
    table.insert(expected_users, MASTER_USER)
    table.insert(expected_credentials, MASTER_CREDENTIAL)
    expect_users(yale_mock_device, expected_users)
    expect_credentials(yale_mock_device, expected_credentials)
    expect_credential_result(yale_mock_device,
      { commandName = "addCredential", statusCode = "success", userIndex = 251, credentialIndex = 251 })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "updateCredential: Yale master code is written to slot 251 and succeeds when the lock reports it changed",
  function()
    seed(yale_mock_device, { MASTER_USER }, { MASTER_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential", args = { 251, 251, "pin", "5678" } } })
    test.socket.zwave:__expect_send(UserCode:Set({
      user_identifier = 251,
      user_code = "5678",
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
    }):build_test_tx(yale_mock_device.id))
    test.wait_for_events()

    queue_master_code_changed(yale_mock_device)
    expect_credential_result(yale_mock_device, { commandName = "updateCredential", statusCode = "success" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "the User Code v2 Master Code Report that follows a master code change is ignored",
  function()
    seed(yale_mock_device, { MASTER_USER }, { MASTER_CREDENTIAL })
    queue_master_code_changed(yale_mock_device)
    test.socket.zwave:__queue_receive({ yale_mock_device.id, UserCodeV2:MasterCodeReport({ master_code = "199111" }) })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

-- ============================================================================
-- protection of the master code
-- ============================================================================

test.register_coroutine_test(
  "deleteCredential: the Yale master code in slot 251 is rejected",
  function()
    seed(yale_mock_device, { MASTER_USER }, { MASTER_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential", args = { 251, "pin" } } })
    expect_credential_result(yale_mock_device, { commandName = "deleteCredential", statusCode = "invalidCommand" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "deleteUser: the user holding the Yale master code is rejected",
  function()
    seed(yale_mock_device, { MASTER_USER }, { MASTER_CREDENTIAL })
    test.socket.capability:__queue_receive({ yale_mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "deleteUser", args = { 251 } } })
    test.socket.capability:__expect_send(yale_mock_device:generate_test_message("main",
      capabilities.lockUsers.commandResult({ commandName = "deleteUser", statusCode = "invalidCommand" },
        { state_change = true, visibility = { displayed = false } })))
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
)

test.register_coroutine_test(
  "all user codes deleted at the lock keeps the Yale master code",
  function()
    seed(yale_mock_device, { MASTER_USER, GUEST_USER }, { MASTER_CREDENTIAL, GUEST_CREDENTIAL })
    test.socket.zwave:__queue_receive({ yale_mock_device.id, Notification:Report({
      notification_type = Notification.notification_type.ACCESS_CONTROL,
      event = access_control_event.ALL_USER_CODES_DELETED,
    }) })
    expect_credentials(yale_mock_device, { MASTER_CREDENTIAL })
    expect_users(yale_mock_device, { MASTER_USER })
    test.wait_for_events()
  end,
  { test_init = make_test_init(yale_mock_device) }
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
  "deleteCredential: a stale credentialIndex 0 is removed locally without sending user identifier 0",
  function()
    seed(mock_device, { { userIndex = 1, userName = "Master Code", userType = "guest" } },
         { { userIndex = 1, credentialIndex = 0, credentialType = "pin" } })
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential", args = { 0, "pin" } } })
    expect_credentials(mock_device, {})
    expect_credential_result(mock_device,
      { commandName = "deleteCredential", statusCode = "success", userIndex = 1, credentialIndex = 0 })
    test.wait_for_events()
  end,
  { test_init = make_test_init(mock_device) }
)

test.run_registered_tests()
