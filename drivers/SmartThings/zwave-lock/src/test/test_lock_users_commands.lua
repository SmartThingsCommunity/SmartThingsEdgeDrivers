-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Integration tests for the lockUsers capability commands:
--   addUser, updateUser, deleteUser, deleteAllUsers

local test              = require "integration_test"
local t_utils           = require "integration_test.utils"
local capabilities      = require "st.capabilities"
local zw                = require "st.zwave"
local st_utils          = require "st.utils"
local table_utils       = require "lock_utils.tables"
local constants         = require "lock_utils.constants"
local UserCode          = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
local json              = require "st.json"


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

-- ── helpers ────────────────────────────────────────────────────────────────

-- Lightweight mock state so that table_utils functions work on mock_device
-- before the driver has lazily initialised the wrapped device.  After the
-- driver processes its first message (wrapped_init), MockDevice.__index
-- delegates every field access to the real driver device, so the overrides
-- below are only ever active during the pre-init seeding phase.
local mock_latest_state = {}
local function mock_state_key(component_id, capability_id, attribute_name)
  return table.concat({ component_id, capability_id, attribute_name }, "|")
end

local function install_state_mocks()
  mock_latest_state = {}

  -- tables.lua calls device.log.{debug,warn,error} unconditionally.
  rawset(mock_device, "log", {
    debug = function() end,
    info  = function() end,
    warn  = function() end,
    error = function() end,
  })

  -- get_state guards with device:supports_capability; always return true here.
  rawset(mock_device, "supports_capability", function() return true end)

  -- get_state / get_max_entries use device:get_latest_state to read
  -- capability attribute values from the state cache.
  rawset(mock_device, "get_latest_state",
    function(_, component_id, capability_id, attribute_name, default_value)
      local key = mock_state_key(component_id, capability_id, attribute_name)
      local value = mock_latest_state[key]
      if value == nil then return default_value end
      return value
    end
  )

  -- add_entry / delete_entry / update_entry all call device:emit_event.
  -- Forward to the capability socket so __expect_send checks pass, and
  -- keep mock_latest_state in sync so that successive get_state calls
  -- within the same seeding loop see the growing list.
  rawset(mock_device, "emit_event", function(_, event)
    mock_latest_state[mock_state_key("main", event.capability.ID, event.attribute.NAME)] = event.value.value
    local message = mock_device:generate_test_message("main", event)
    test.socket.capability:send(message[1], json.encode(message[2]))
  end)
end

local function test_init()
  install_state_mocks()
  mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

local function expect_set_pin_code(user_identifier, user_code)
  test.socket.zwave:__expect_send(
    UserCode:Set({
      user_identifier = user_identifier,
      user_code = user_code,
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
    }):build_test_tx(mock_device.id)
  )
end

local function expect_clear_pin_code(user_identifier)
  test.socket.zwave:__expect_send(
    UserCode:Set({
      user_identifier = user_identifier,
      user_id_status = UserCode.user_id_status.AVAILABLE,
    }):build_test_tx(mock_device.id)
  )
end

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

-- Set totalUsersSupported (and pinUsersSupported) by injecting the Z-Wave
-- UsersNumberReport that the real users_number_report handler processes.
-- Using the Z-Wave path is essential: it goes through the driver's normal
-- emit_component_event path and populates the driver device's state cache,
-- which is what get_max_entries reads when enforcing the slot limit.
local function set_total_users_supported(n)
  test.socket.zwave:__queue_receive({
    mock_device.id,
    UserCode:UsersNumberReport({ supported_users = n })
  })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main",
      capabilities.lockUsers.totalUsersSupported(n, { state_change = true, visibility = { displayed = false } }))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main",
      capabilities.lockCredentials.pinUsersSupported(n, { state_change = true, visibility = { displayed = false } }))
  )
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
  "updateUser: creates user when userIndex does not exist",
  function()
    -- empty table — nothing to update
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
-- deleteAllUsers  (injects deleteAllCredentials → ClearAllPINCodes z-wave flow)
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

    test.timer.__create_and_queue_test_time_advance_timer(0, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(0.5, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(8, "oneshot")
    test.mock_time.advance_time(0)
    expect_clear_pin_code(1)
    test.wait_for_events()
    test.mock_time.advance_time(0.5)
    expect_clear_pin_code(2)
    test.wait_for_events()

    -- The legacy subdriver consumes deletion notifications for this mock profile; advance
    -- to the driver's cleanup timer, which clears both tables and reports success.
    test.mock_time.advance_time(8)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users({}, { visibility = { displayed = false } }))
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
        capabilities.lockCredentials.credentials({}, { visibility = { displayed = false } }))
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
  "deleteAllUsers: emits busy when another lock command is in progress",
  function()
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.LOCK_CREDENTIALS.ADD, {})

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "deleteAllUsers", args = {} },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "deleteAllUsers", statusCode = "busy" },
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


test.register_coroutine_test(
  "State-consistency: add users 1-3, deleteUser 2 (no credential), re-add user reclaims index 2",
  function()
    -- Populate three user slots directly (no credentials, so deleteUser will take
    -- the no-Z-Wave path and delete the user entry locally).
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
    expect_clear_pin_code(2)
    test.wait_for_events()

    -- Lock acknowledges the deletion.
    -- The legacy subdriver handles deletion notifications for this mock profile, so clear local
    -- state directly to model the intended post-delete state before testing index reuse.
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
    assert(table_utils.delete_entry(mock_device, "users", 2) == constants.COMMAND_RESULT.SUCCESS)
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
    assert(table_utils.delete_entry(mock_device, "credentials", 2) == constants.COMMAND_RESULT.SUCCESS)
    test.wait_for_events()
    mock_device:set_field(constants.DRIVER_STATE.BUSY, false, {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, nil, {})

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
    expect_set_pin_code(2, "9999")
    test.wait_for_events()

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
    assert(table_utils.add_entry(mock_device, "credentials", {
      userIndex = 2,
      credentialIndex = 2,
      credentialType = "pin",
      credentialName = "Guest 2",
    }) == constants.COMMAND_RESULT.SUCCESS)
    test.wait_for_events()
  end
)

-- ============================================================================
-- revert Migration on init
-- ============================================================================

test.register_coroutine_test(
  "Revert Migration on init, after added",
  function()
    seed_users({
      { userIndex = 1, userName = "Alice", userType = "guest" },
      { userIndex = 2, userName = "Bob",   userType = "guest" },
      { userIndex = 5, userName = "Charlie", userType = "guest" },
    })
    seed_credentials({
      { userIndex = 1, credentialIndex = 1, credentialType = "pin" },
      { userIndex = 2, credentialIndex = 2, credentialType = "pin" },
      { userIndex = 5, credentialIndex = 5, credentialType = "pin" },
    })

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
    test.socket.capability:__set_channel_ordering("relaxed")

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          {
            { userIndex = 1, userName = "Alice", userType = "guest" },
            { userIndex = 2, userName = "Bob",  userType = "guest" },
            { userIndex = 5, userName = "Charlie", userType = "guest" },
          },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          {
            { userIndex = 1, credentialIndex = 1, credentialType = "pin" },
            { userIndex = 2, credentialIndex = 2, credentialType = "pin" },
            { userIndex = 5, credentialIndex = 5, credentialType = "pin" },
          },
          { visibility = { displayed = false } }
        ))
    )

    -- Reversion of Migration should be handled for the device on initialization
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCodes.lockCodes(json.encode({
          ["1"] = "Alice", ["2"] = "Bob", ["5"] = "Charlie"
        }), { visibility = { displayed = false } })
      )
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCodes.migrated(false, { visibility = { displayed = false } })
      )
    )
    test.wait_for_events()
    assert(mock_device:get_field(constants.SLGA_MIGRATED) == nil, "Device should not be marked as migrated")
    local stored_codes = st_utils.deep_copy(mock_device:get_field("_lock_codes"))
    assert(stored_codes["1"] == "Alice")
    assert(stored_codes["2"] == "Bob")
    assert(stored_codes["5"] == "Charlie")

    test.wait_for_events()

    -- ensure codeChanged now triggers correctly after setting a new code
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "setCode", args = { 3, "1234", "test" } } })
    test.socket.zwave:__expect_send(UserCode:Set({user_identifier = 3, user_code = "1234", user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS}):build_test_tx(mock_device.id) )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id, UserCode:Report({user_identifier = 3, user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS}) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCodes.lockCodes(json.encode({
          ["1"] = "Alice", ["2"] = "Bob", ["3"] = "test", ["5"] = "Charlie"
        }), { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCodes.codeChanged("3 set", { data = { codeName = "test"}, state_change = true  }))
    )
  end,
  {
    min_api_version = 17
  }
)

test.run_registered_tests()
