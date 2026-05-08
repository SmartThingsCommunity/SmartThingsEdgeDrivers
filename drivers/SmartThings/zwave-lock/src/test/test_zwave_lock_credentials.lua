-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.UserCode
local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
--- @type st.zwave.CommandClass.DoorLock
local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local t_utils = require "integration_test.utils"
local access_control_event = Notification.event.access_control
local lock_utils = require "zwave_lock_utils"

test.disable_startup_messages()

local zwave_lock_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = zw.DOOR_LOCK},
      {value = zw.USER_CODE},
      {value = zw.NOTIFICATION}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("base-lock-tamper.yml"),
  _provisioning_state = "TYPED",
  zwave_endpoints = zwave_lock_endpoints
})

-- Tracks expected users and credentials across test helpers
local test_credential_index
local test_credentials
local test_users

local function test_init()
  test.mock_device.add_test_device(mock_device)
  test_credential_index = 1
  test_credentials = {}
  test_users = {}
end

test.set_test_init_function(test_init)

-- Simulate the device being added (runs lifecycle, loads initial state)
local function added()
  test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockCodes.migrated(true, { visibility = { displayed = false } })))
  test.socket.zwave:__expect_send(DoorLock:OperationGet({}):build_test_tx(mock_device.id))
  test.socket.zwave:__expect_send(Battery:Get({}):build_test_tx(mock_device.id))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.tamperAlert.tamper.clear()))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockCredentials.supportedCredentials({"pin"}, { visibility = { displayed = false } })))
  test.wait_for_events()
  test.mock_time.advance_time(2)
  test.socket.zwave:__expect_send(UserCode:UsersNumberGet({}):build_test_tx(mock_device.id))
  for i = 1, 8 do
    test.socket.zwave:__expect_send(UserCode:Get({user_identifier = i}):build_test_tx(mock_device.id))
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id, UserCode:Report({
      user_identifier = i,
      user_id_status = UserCode.user_id_status.AVAILABLE
    })})
  end
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockUsers.users({}, { state_change = true, visibility = { displayed = true } })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockCredentials.credentials({}, { state_change = true, visibility = { displayed = true } })))
  test.wait_for_events()
end

-- Helper: add a credential (user_index 0 = auto-create guest user).
-- Uses a Notification report (the primary confirmation path for add).
-- Updates test_users and test_credentials tracking tables.
local function add_credential(user_index)
  local expected_user_index = (user_index == 0) and test_credential_index or user_index
  test.socket.capability:__queue_receive({mock_device.id, {
    capability = capabilities.lockCredentials.ID,
    command = "addCredential",
    args = { user_index, "guest", "pin", "1234" }
  }})
  test.socket.zwave:__expect_send(
    UserCode:Set({
      user_identifier = test_credential_index,
      user_code = "1234",
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
    }):build_test_tx(mock_device.id)
  )
  test.wait_for_events()

  -- Notification confirms the code was added; v1_alarm_level encodes the credential index
  local payload = "\x70\x01\x00\xFF\x06\x0E\x00\x00"
  payload = payload:sub(1, 1) .. string.char(test_credential_index) .. payload:sub(3)
  test.socket.zwave:__queue_receive({mock_device.id,
    Notification:Report({
      notification_type = Notification.notification_type.ACCESS_CONTROL,
      event = access_control_event.NEW_USER_CODE_ADDED,
      payload = payload
    })
  })

  if user_index == 0 then
    table.insert(test_users, {
      userIndex = expected_user_index,
      userName = "Guest" .. expected_user_index,
      userType = "guest"
    })
  end
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockUsers.users(test_users, { state_change = true, visibility = { displayed = true } })))

  table.insert(test_credentials, {
    userIndex = expected_user_index,
    credentialIndex = test_credential_index,
    credentialType = "pin"
  })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockCredentials.credentials(test_credentials, { state_change = true, visibility = { displayed = true } })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockCredentials.commandResult(
      { commandName = "addCredential", statusCode = "success",
        credentialIndex = test_credential_index, userIndex = expected_user_index },
      { state_change = true, visibility = { displayed = true } }
    )))
  test.wait_for_events()
  test_credential_index = test_credential_index + 1
end

-- Helper: add a named user and return userIndex
local function add_user(user_name)
  local user_index = #test_users + 1
  test.socket.capability:__queue_receive({mock_device.id, {
    capability = capabilities.lockUsers.ID,
    command = "addUser",
    args = { user_name, "guest" }
  }})
  table.insert(test_users, { userIndex = user_index, userType = "guest", userName = user_name })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockUsers.users(test_users, { state_change = true, visibility = { displayed = true } })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockUsers.commandResult(
      { commandName = "addUser", statusCode = "success", userIndex = user_index },
      { state_change = true, visibility = { displayed = true } }
    )))
  test.wait_for_events()
  return user_index
end

-- ─────────────────────────────────────────────────────────────────────────────
-- addCredential tests
-- ─────────────────────────────────────────────────────────────────────────────

test.register_coroutine_test(
  "addCredential: auto-creates guest user and assigns sequential credential indices",
  function()
    added()
    add_credential(0)  -- credential 1, user 1 (Guest1)
    add_credential(0)  -- credential 2, user 2 (Guest2)
    add_credential(0)  -- credential 3, user 3 (Guest3)
    -- All three should exist in state
    assert(lock_utils.get_credential(mock_device, 1) ~= nil, "credential 1 should exist")
    assert(lock_utils.get_credential(mock_device, 2) ~= nil, "credential 2 should exist")
    assert(lock_utils.get_credential(mock_device, 3) ~= nil, "credential 3 should exist")
    assert(lock_utils.get_user(mock_device, 1) ~= nil, "user 1 should exist")
    assert(lock_utils.get_user(mock_device, 2) ~= nil, "user 2 should exist")
    assert(lock_utils.get_user(mock_device, 3) ~= nil, "user 3 should exist")
  end
)

test.register_coroutine_test(
  "addCredential: adding second credential for existing user returns STATUS_OCCUPIED",
  function()
    added()
    local user_index = add_user("TestUser1")
    -- add the first credential for this user, should succeed
    add_credential(user_index)

    -- attempt to add a second credential for the same user (should fail with OCCUPIED)
    test.socket.capability:__queue_receive({mock_device.id, {
      capability = capabilities.lockCredentials.ID,
      command = "addCredential",
      args = { user_index, "guest", "pin", "9999" }
    }})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.commandResult(
        { commandName = "addCredential", statusCode = "occupied" },
        { state_change = true, visibility = { displayed = true } }
      )))
    test.wait_for_events()

    -- only one credential should be present for this user
    local count = 0
    for _, cred in pairs(lock_utils.get_credentials(mock_device)) do
      if cred.userIndex == user_index then count = count + 1 end
    end
    assert(count == 1, "user should have exactly one credential, got " .. count)
  end
)

test.register_coroutine_test(
  "addCredential: adding credential for non-existent user returns STATUS_FAILURE",
  function()
    added()
    test.socket.capability:__queue_receive({mock_device.id, {
      capability = capabilities.lockCredentials.ID,
      command = "addCredential",
      args = { 99, "guest", "pin", "1234" }  -- user 99 does not exist
    }})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.commandResult(
        { commandName = "addCredential", statusCode = "failure" },
        { state_change = true, visibility = { displayed = true } }
      )))
    test.wait_for_events()
  end
)

-- ─────────────────────────────────────────────────────────────────────────────
-- updateCredential tests
-- ─────────────────────────────────────────────────────────────────────────────

test.register_coroutine_test(
  "updateCredential: updates code in-place without creating a duplicate credential entry",
  function()
    added()
    add_credential(0)  -- credential 1, user 1

    -- update credential 1 with a new pin
    test.socket.capability:__queue_receive({mock_device.id, {
      capability = capabilities.lockCredentials.ID,
      command = "updateCredential",
      args = { 1, 1, "pin", "9999" }
    }})
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 1,
        user_code = "9999",
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()

    -- lock acknowledges code update at index 1 (v1_alarm_level = 1)
    local payload = "\x70\x01\x00\xFF\x06\x0E\x00\x00"  -- v1_alarm_level byte = 1
    test.socket.zwave:__queue_receive({mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = access_control_event.NEW_USER_CODE_ADDED,
        payload = payload
      })
    })
    -- credential count must remain 1 (no duplicates)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockUsers.users(
        {{ userIndex = 1, userName = "Guest1", userType = "guest" }},
        { state_change = true, visibility = { displayed = true } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.credentials(
        {{ userIndex = 1, credentialIndex = 1, credentialType = "pin" }},
        { state_change = true, visibility = { displayed = true } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.commandResult(
        { commandName = "updateCredential", statusCode = "success",
          credentialIndex = 1, userIndex = 1 },
        { state_change = true, visibility = { displayed = true } }
      )))
    test.wait_for_events()

    -- verify only one credential exists in driver state
    local credentials = lock_utils.get_credentials(mock_device)
    local count = 0
    for _ in pairs(credentials) do count = count + 1 end
    assert(count == 1, "should have exactly 1 credential after update, got " .. count)
    assert(credentials[1].credentialIndex == 1, "credential index should still be 1")
  end
)

test.register_coroutine_test(
  "updateCredential: returns failure when credential does not exist",
  function()
    added()
    test.socket.capability:__queue_receive({mock_device.id, {
      capability = capabilities.lockCredentials.ID,
      command = "updateCredential",
      args = { 99, 1, "pin", "9999" }  -- credential index 99 does not exist
    }})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.commandResult(
        { commandName = "updateCredential", statusCode = "failure" },
        { state_change = true, visibility = { displayed = true } }
      )))
    test.wait_for_events()
  end
)

-- ─────────────────────────────────────────────────────────────────────────────
-- deleteCredential tests
-- ─────────────────────────────────────────────────────────────────────────────

test.register_coroutine_test(
  "deleteCredential: deletes the correct credential by credentialIndex",
  function()
    added()
    add_credential(0)  -- credential 1, user 1
    add_credential(0)  -- credential 2, user 2

    -- delete credential 1, leaving credential 2 intact
    test.socket.capability:__queue_receive({mock_device.id, {
      capability = capabilities.lockCredentials.ID,
      command = "deleteCredential",
      args = { 1, "pin" }
    }})
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 1,
        user_id_status = UserCode.user_id_status.AVAILABLE
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()

    -- lock confirms deletion of credential index 1 (v1_alarm_level = 1)
    local payload = "\x21\x01\x00\xFF\x06\x0D\x00\x00"
    test.socket.zwave:__queue_receive({mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = access_control_event.SINGLE_USER_CODE_DELETED,
        payload = payload
      })
    })
    -- user 1 deleted, user 2 remains
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockUsers.users(
        {{ userIndex = 2, userName = "Guest2", userType = "guest" }},
        { state_change = true, visibility = { displayed = true } })))
    -- credential 1 deleted, credential 2 remains
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.credentials(
        {{ userIndex = 2, credentialIndex = 2, credentialType = "pin" }},
        { state_change = true, visibility = { displayed = true } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.commandResult(
        { commandName = "deleteCredential", statusCode = "success",
          credentialIndex = 1, userIndex = 1 },
        { state_change = true, visibility = { displayed = true } }
      )))
    test.wait_for_events()

    assert(lock_utils.get_credential(mock_device, 1) == nil, "credential 1 should be deleted")
    assert(lock_utils.get_credential(mock_device, 2) ~= nil, "credential 2 should remain")
    assert(lock_utils.get_user(mock_device, 1) == nil, "user 1 should be deleted")
    assert(lock_utils.get_user(mock_device, 2) ~= nil, "user 2 should remain")
  end
)

test.register_coroutine_test(
  "deleteCredential: deletes the correct credential when deleting the second of two",
  function()
    added()
    add_credential(0)  -- credential 1, user 1
    add_credential(0)  -- credential 2, user 2

    -- delete credential 2, leaving credential 1 intact
    test.socket.capability:__queue_receive({mock_device.id, {
      capability = capabilities.lockCredentials.ID,
      command = "deleteCredential",
      args = { 2, "pin" }
    }})
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 2,
        user_id_status = UserCode.user_id_status.AVAILABLE
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()

    -- lock confirms deletion of credential index 2 (v1_alarm_level = 2)
    local payload = "\x21\x02\x00\xFF\x06\x0D\x00\x00"
    test.socket.zwave:__queue_receive({mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = access_control_event.SINGLE_USER_CODE_DELETED,
        payload = payload
      })
    })
    -- user 2 deleted, user 1 remains
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockUsers.users(
        {{ userIndex = 1, userName = "Guest1", userType = "guest" }},
        { state_change = true, visibility = { displayed = true } })))
    -- credential 2 deleted, credential 1 remains
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.credentials(
        {{ userIndex = 1, credentialIndex = 1, credentialType = "pin" }},
        { state_change = true, visibility = { displayed = true } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.commandResult(
        { commandName = "deleteCredential", statusCode = "success",
          credentialIndex = 2, userIndex = 2 },
        { state_change = true, visibility = { displayed = true } }
      )))
    test.wait_for_events()

    assert(lock_utils.get_credential(mock_device, 1) ~= nil, "credential 1 should remain")
    assert(lock_utils.get_credential(mock_device, 2) == nil, "credential 2 should be deleted")
    assert(lock_utils.get_user(mock_device, 1) ~= nil, "user 1 should remain")
    assert(lock_utils.get_user(mock_device, 2) == nil, "user 2 should be deleted")
  end
)

test.register_coroutine_test(
  "deleteCredential: also deletes the associated guest user",
  function()
    added()
    add_credential(0)  -- creates guest user 1 + credential 1

    test.socket.capability:__queue_receive({mock_device.id, {
      capability = capabilities.lockCredentials.ID,
      command = "deleteCredential",
      args = { 1, "pin" }
    }})
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 1,
        user_id_status = UserCode.user_id_status.AVAILABLE
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()

    local payload = "\x21\x01\x00\xFF\x06\x0D\x00\x00"
    test.socket.zwave:__queue_receive({mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = access_control_event.SINGLE_USER_CODE_DELETED,
        payload = payload
      })
    })
    -- both user and credential lists should now be empty
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockUsers.users({}, { state_change = true, visibility = { displayed = true } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.credentials({}, { state_change = true, visibility = { displayed = true } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.commandResult(
        { commandName = "deleteCredential", statusCode = "success",
          credentialIndex = 1, userIndex = 1 },
        { state_change = true, visibility = { displayed = true } }
      )))
    test.wait_for_events()

    assert(lock_utils.get_user(mock_device, 1) == nil, "associated user should also be deleted")
    assert(lock_utils.get_credential(mock_device, 1) == nil, "credential should be deleted")
  end
)

test.register_coroutine_test(
  "deleteCredential: returns failure for non-existent credential index",
  function()
    added()
    test.socket.capability:__queue_receive({mock_device.id, {
      capability = capabilities.lockCredentials.ID,
      command = "deleteCredential",
      args = { 99, "pin" }
    }})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.commandResult(
        { commandName = "deleteCredential", statusCode = "failure" },
        { state_change = true, visibility = { displayed = true } }
      )))
    test.wait_for_events()
  end
)

-- ─────────────────────────────────────────────────────────────────────────────
-- deleteAllCredentials tests
-- ─────────────────────────────────────────────────────────────────────────────

test.register_coroutine_test(
  "deleteAllCredentials: deletes all credentials and all associated users",
  function()
    added()
    add_credential(0)  -- credential 1, user 1
    add_credential(0)  -- credential 2, user 2

    test.socket.capability:__queue_receive({mock_device.id, {
      capability = capabilities.lockCredentials.ID,
      command = "deleteAllCredentials",
      args = {}
    }})
    -- Both Z-wave Set commands are sent immediately (no timer delay between them)
    test.socket.zwave:__expect_send(
      UserCode:Set({ user_identifier = 1, user_id_status = UserCode.user_id_status.AVAILABLE
      }):build_test_tx(mock_device.id))
    test.socket.zwave:__expect_send(
      UserCode:Set({ user_identifier = 2, user_id_status = UserCode.user_id_status.AVAILABLE
      }):build_test_tx(mock_device.id))
    -- A clear_busy_state timer is set for (delay + 4) = (2+2+4) = 8 seconds
    test.timer.__create_and_queue_test_time_advance_timer(8, "oneshot")
    test.wait_for_events()

    -- Lock acknowledges deletion of credential 1 (v1_alarm_level = 1)
    test.socket.zwave:__queue_receive({mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = access_control_event.SINGLE_USER_CODE_DELETED,
        payload = "\x21\x01\x00\xFF\x06\x0D\x00\x00"
      })
    })
    -- user 1 and credential 1 deleted; user 2 and credential 2 still present
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockUsers.users(
        {{ userIndex = 2, userName = "Guest2", userType = "guest" }},
        { state_change = true, visibility = { displayed = true } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.credentials(
        {{ userIndex = 2, credentialIndex = 2, credentialType = "pin" }},
        { state_change = true, visibility = { displayed = true } })))
    -- commandResult must NOT be emitted here (command is still in progress)
    test.wait_for_events()

    -- Lock acknowledges deletion of credential 2 (v1_alarm_level = 2)
    test.socket.zwave:__queue_receive({mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = access_control_event.SINGLE_USER_CODE_DELETED,
        payload = "\x21\x02\x00\xFF\x06\x0D\x00\x00"
      })
    })
    -- Now both user 2 and credential 2 are deleted
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockUsers.users({}, { state_change = true, visibility = { displayed = true } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.credentials({}, { state_change = true, visibility = { displayed = true } })))
    -- commandResult still must NOT be emitted here (timer hasn't fired yet)
    test.wait_for_events()

    -- Timer fires -> commandResult emitted
    test.mock_time.advance_time(8)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.commandResult(
        { commandName = "deleteAllCredentials", statusCode = "success" },
        { state_change = true, visibility = { displayed = true } }
      )))
    test.wait_for_events()

    -- Verify final state: everything deleted
    assert(lock_utils.get_credential(mock_device, 1) == nil, "credential 1 should be deleted")
    assert(lock_utils.get_credential(mock_device, 2) == nil, "credential 2 should be deleted")
    assert(lock_utils.get_user(mock_device, 1) == nil, "user 1 should be deleted")
    assert(lock_utils.get_user(mock_device, 2) == nil, "user 2 should be deleted")
  end
)

test.register_coroutine_test(
  "deleteAllCredentials: handles ALL_USER_CODES_DELETED notification from lock",
  function()
    added()
    add_credential(0)  -- credential 1, user 1
    add_credential(0)  -- credential 2, user 2

    test.socket.capability:__queue_receive({mock_device.id, {
      capability = capabilities.lockCredentials.ID,
      command = "deleteAllCredentials",
      args = {}
    }})
    test.socket.zwave:__expect_send(
      UserCode:Set({ user_identifier = 1, user_id_status = UserCode.user_id_status.AVAILABLE
      }):build_test_tx(mock_device.id))
    test.socket.zwave:__expect_send(
      UserCode:Set({ user_identifier = 2, user_id_status = UserCode.user_id_status.AVAILABLE
      }):build_test_tx(mock_device.id))
    test.timer.__create_and_queue_test_time_advance_timer(8, "oneshot")
    test.wait_for_events()

    -- Some locks respond with ALL_USER_CODES_DELETED instead of individual events
    -- ALL_USER_CODES_DELETED = 0x0C = 12
    test.socket.zwave:__queue_receive({mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = access_control_event.ALL_USER_CODES_DELETED,
        payload = "\x00\x00\x00\xFF\x06\x0C\x00\x00"
      })
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockUsers.users({}, { state_change = true, visibility = { displayed = true } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.credentials({}, { state_change = true, visibility = { displayed = true } })))
    test.wait_for_events()

    test.mock_time.advance_time(8)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.commandResult(
        { commandName = "deleteAllCredentials", statusCode = "success" },
        { state_change = true, visibility = { displayed = true } }
      )))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "deleteAllCredentials: no-op when there are no credentials",
  function()
    added()
    test.socket.capability:__queue_receive({mock_device.id, {
      capability = capabilities.lockCredentials.ID,
      command = "deleteAllCredentials",
      args = {}
    }})
    -- No Z-wave sends since there are no credentials
    -- Timer fires immediately (delay = 0, so call_with_delay(4, ...))
    test.timer.__create_and_queue_test_time_advance_timer(4, "oneshot")
    test.wait_for_events()
    test.mock_time.advance_time(4)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.commandResult(
        { commandName = "deleteAllCredentials", statusCode = "success" },
        { state_change = true, visibility = { displayed = true } }
      )))
    test.wait_for_events()
  end
)

test.run_registered_tests()
