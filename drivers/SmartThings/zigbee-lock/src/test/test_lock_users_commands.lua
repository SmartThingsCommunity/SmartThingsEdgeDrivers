-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Integration tests for the lockUsers capability commands:
--   addUser, updateUser, deleteUser, deleteAllUsers

local test              = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils           = require "integration_test.utils"
local capabilities      = require "st.capabilities"
local clusters          = require "st.zigbee.zcl.clusters"
local DoorLock          = clusters.DoorLock
local table_utils       = require "lock_utils.tables"
local constants         = require "lock_utils.constants"

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("base-lock.yml"),
})
zigbee_test_utils.prepare_zigbee_env_info()

-- ── helpers ────────────────────────────────────────────────────────────────

local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

-- Directly insert users into the device state via table_utils (mirrors test_lock_tables.lua).
-- Consumes the resulting capability events so the socket queue stays clean.
local function seed_users(entries)
  for _, entry in ipairs(entries) do
    local so_far = {}
    for _, e in ipairs(entries) do
      table.insert(so_far, e)
      if e == entry then break end
    end
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(so_far, { visibility = { displayed = false } }))
    )
    assert(table_utils.add_entry(mock_device, "users", entry) == constants.COMMAND_RESULT.SUCCESS,
      "seed_users: add_entry failed for userIndex=" .. tostring(entry.userIndex))
  end
  test.wait_for_events()
end

-- Directly insert credentials into the device state.
local function seed_credentials(entries)
  for _, entry in ipairs(entries) do
    local so_far = {}
    for _, e in ipairs(entries) do
      table.insert(so_far, e)
      if e == entry then break end
    end
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(so_far, { visibility = { displayed = false } }))
    )
    assert(table_utils.add_entry(mock_device, "credentials", entry) == constants.COMMAND_RESULT.SUCCESS,
      "seed_credentials: add_entry failed for credentialIndex=" .. tostring(entry.credentialIndex))
  end
  test.wait_for_events()
end

-- Set totalUsersSupported on the mock device and consume the resulting event.
local function set_total_users_supported(n)
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main",
      capabilities.lockUsers.totalUsersSupported(n, { visibility = { displayed = false } }))
  )
  mock_device:emit_event(capabilities.lockUsers.totalUsersSupported(n, { visibility = { displayed = false } }))
  test.wait_for_events()
end

-- ============================================================================
-- addUser
-- ============================================================================

test.register_coroutine_test(
  "addUser: assigns userIndex 1 for the first user and emits a success commandResult",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "addUser", args = { "Alice", "guest" } },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Alice", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "addUser: assigns the next sequential userIndex when users already exist",
  function()
    seed_users({ { userIndex = 1, userName = "Alice", userType = "guest" } })

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "addUser", args = { "Bob", "guest" } },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          {
            { userIndex = 1, userName = "Alice", userType = "guest" },
            { userIndex = 2, userName = "Bob",   userType = "guest" },
          },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 2 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "addUser: fills a gap left by a deleted user rather than appending beyond max",
  function()
    -- Seed indices 1 and 3; index 2 is the expected gap to fill
    seed_users({
      { userIndex = 1, userName = "Alice", userType = "guest" },
      { userIndex = 3, userName = "Carol", userType = "guest" },
    })

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "addUser", args = { "Bob", "guest" } },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          {
            { userIndex = 1, userName = "Alice", userType = "guest" },
            { userIndex = 3, userName = "Carol", userType = "guest" },
            { userIndex = 2, userName = "Bob",   userType = "guest" },
          },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 2 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "addUser: returns resourceExhausted when totalUsersSupported has been reached",
  function()
    set_total_users_supported(2)
    seed_users({
      { userIndex = 1, userName = "Alice", userType = "guest" },
      { userIndex = 2, userName = "Bob",   userType = "guest" },
    })

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "addUser", args = { "Carol", "guest" } },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "resourceExhausted" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- updateUser
-- ============================================================================

test.register_coroutine_test(
  "updateUser: updates an existing user and emits a success commandResult with userIndex",
  function()
    seed_users({
      { userIndex = 1, userName = "Alice", userType = "guest" },
      { userIndex = 2, userName = "Bob",   userType = "guest" },
    })

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "updateUser", args = { 1, "AliceUpdated", "guest" } },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          {
            { userIndex = 1, userName = "AliceUpdated", userType = "guest" },
            { userIndex = 2, userName = "Bob",           userType = "guest" },
          },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "updateUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "updateUser: adds user and returns success when the target userIndex does not exist",
  function()
    -- empty table, add user
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "updateUser", args = { 99, "Ghost", "guest" } },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          {
            { userIndex = 99, userName = "Ghost", userType = "guest" },
          },
          { visibility = { displayed = false } }
        ))
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "updateUser", statusCode = "success", userIndex = 99 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "updateUser: can change a user's type as well as name",
  function()
    seed_users({ { userIndex = 1, userName = "Alice", userType = "guest" } })

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "updateUser", args = { 1, "Alice", "adminMember" } },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Alice", userType = "adminMember" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "updateUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- deleteUser (no associated credential — pure local delete)
-- ============================================================================

test.register_coroutine_test(
  "deleteUser: removes a user with no credential and emits a success commandResult with userIndex",
  function()
    seed_users({
      { userIndex = 1, userName = "Alice", userType = "guest" },
      { userIndex = 2, userName = "Bob",   userType = "guest" },
    })

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "deleteUser", args = { 1 } },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 2, userName = "Bob", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "deleteUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "deleteUser: returns failure when the target userIndex is not in the users table",
  function()
    -- empty table
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "deleteUser", args = { 99 } },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "deleteUser", statusCode = "failure" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- deleteAllUsers  (injects deleteAllCredentials → ClearAllPINCodes zigbee flow)
-- ============================================================================

test.register_coroutine_test(
  "deleteAllUsers: sends ClearAllPINCodes and emits success for both users and credentials on PASS",
  function()
    seed_users({
      { userIndex = 1, userName = "Alice", userType = "guest" },
      { userIndex = 2, userName = "Bob",   userType = "guest" },
    })
    seed_credentials({
      { userIndex = 1, credentialIndex = 1, credentialType = "pin" },
      { userIndex = 2, credentialIndex = 2, credentialType = "pin" },
    })

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "deleteAllUsers", args = {} },
    })

    -- deleteAllUsers injects deleteAllCredentials, which sends ClearAllPINCodes
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearAllPINCodes(mock_device) })
    test.wait_for_events()

    local ResponseStatus = DoorLock.types.DrlkPassFailStatus
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.ClearAllPINCodesResponse.build_test_rx(mock_device, ResponseStatus.PASS),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users({}, { visibility = { displayed = false } }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials({}, { visibility = { displayed = false } }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "deleteAllUsers", statusCode = "success" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteAllCredentials", statusCode = "success" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "deleteAllUsers: emits failure for both users and credentials when the lock returns FAIL",
  function()
    seed_users({ { userIndex = 1, userName = "Alice", userType = "guest" } })
    seed_credentials({ { userIndex = 1, credentialIndex = 1, credentialType = "pin" } })

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "deleteAllUsers", args = {} },
    })

    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearAllPINCodes(mock_device) })
    test.wait_for_events()

    local ResponseStatus = DoorLock.types.DrlkPassFailStatus
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.ClearAllPINCodesResponse.build_test_rx(mock_device, ResponseStatus.FAIL),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "deleteAllUsers", statusCode = "failure" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteAllCredentials", statusCode = "failure" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- State-consistency: add → delete → re-add (indices 1, 2, 3 lifecycle)
-- ============================================================================
--
-- These tests verify that the users and credentials tables stay in sync
-- through a full lifecycle: populate three slots, remove the middle one,
-- then re-add a user and credential into the freed slot.  The goal is to
-- confirm there is no stale index state that would cause duplicate entries,
-- wrong slot assignment, or mismatched user↔credential links.

local DoorLockUserStatus = DoorLock.types.DrlkUserStatus
local DoorLockUserType   = DoorLock.types.DrlkUserType
local SetCodeStatus      = DoorLock.types.DrlkSetCodeStatus
local ResponseStatus     = DoorLock.types.DrlkPassFailStatus

test.register_coroutine_test(
  "State-consistency: add users 1-3, deleteUser 2 (no credential), re-add user reclaims index 2",
  function()
    -- Populate three user slots directly (no credentials, so deleteUser will take
    -- the no-ZigBee path and delete the user entry locally).
    seed_users({
      { userIndex = 1, userName = "Alice", userType = "guest" },
      { userIndex = 2, userName = "Bob",   userType = "guest" },
      { userIndex = 3, userName = "Carol", userType = "guest" },
    })

    -- Delete user at index 2; no credential is linked so this is a pure local delete.
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "deleteUser", args = { 2 } },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          {
            { userIndex = 1, userName = "Alice", userType = "guest" },
            { userIndex = 3, userName = "Carol", userType = "guest" },
          },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "deleteUser", statusCode = "success", userIndex = 2 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()

    -- Re-add a user.  next_index sees occupied = {1, 3}, so it assigns index 2.
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "addUser", args = { "Dave", "guest" } },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          {
            { userIndex = 1, userName = "Alice", userType = "guest" },
            { userIndex = 3, userName = "Carol", userType = "guest" },
            { userIndex = 2, userName = "Dave",  userType = "guest" },
          },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 2 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "State-consistency: add users+credentials 1-3, deleteUser 2 (with credential), re-add user+credential reclaims index 2 cleanly",
  function()
    -- Populate three user and credential slots.
    seed_users({
      { userIndex = 1, userName = "Alice", userType = "guest" },
      { userIndex = 2, userName = "Bob",   userType = "guest" },
      { userIndex = 3, userName = "Carol", userType = "guest" },
    })
    seed_credentials({
      { userIndex = 1, credentialIndex = 1, credentialType = "pin" },
      { userIndex = 2, credentialIndex = 2, credentialType = "pin" },
      { userIndex = 3, credentialIndex = 3, credentialType = "pin" },
    })

    -- Delete user at index 2.  The handler finds a linked credential and injects
    -- deleteCredential, which sends ClearPINCode to the lock.
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "deleteUser", args = { 2 } },
    })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.SendPINOverTheAir:write(mock_device, true) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearPINCode(mock_device, 2) })
    test.wait_for_events()

    -- Lock acknowledges the deletion.
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.ClearPINCodeResponse.build_test_rx(mock_device, ResponseStatus.PASS),
    })
    -- clear_pin_code_response (LOCK_USERS.DELETE path): deletes credentials first, then user.
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          {
            { userIndex = 1, credentialIndex = 1, credentialType = "pin" },
            { userIndex = 3, credentialIndex = 3, credentialType = "pin" },
          },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          {
            { userIndex = 1, userName = "Alice", userType = "guest" },
            { userIndex = 3, userName = "Carol", userType = "guest" },
          },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "deleteUser", statusCode = "success", userIndex = 2 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteCredential", statusCode = "success", credentialIndex = 2, userIndex = 2 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()

    -- Re-add a user.  next_index sees occupied = {1, 3} and assigns index 2.
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "addUser", args = { "Dave", "guest" } },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          {
            { userIndex = 1, userName = "Alice", userType = "guest" },
            { userIndex = 3, userName = "Carol", userType = "guest" },
            { userIndex = 2, userName = "Dave",  userType = "guest" },
          },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 2 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()

    -- Re-add a credential for the new user at slot 2.  The old credential at
    -- credentialIndex 2 was cleanly removed, so add_entry must succeed without
    -- returning OCCUPIED or any stale-state error.
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 2, "guest", "pin", "9999" } },
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
        2, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "9999"),
    })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetPINCodeResponse.build_test_rx(mock_device, SetCodeStatus.SUCCESS),
    })
    -- Credential is freshly added at index 2 alongside the retained entries at 1 and 3.
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          {
            { userIndex = 1, credentialIndex = 1, credentialType = "pin" },
            { userIndex = 3, credentialIndex = 3, credentialType = "pin" },
            { userIndex = 2, credentialIndex = 2, credentialType = "pin", credentialName = "Guest 2" },
          },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", userIndex = 2, credentialIndex = 2 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.run_registered_tests()
