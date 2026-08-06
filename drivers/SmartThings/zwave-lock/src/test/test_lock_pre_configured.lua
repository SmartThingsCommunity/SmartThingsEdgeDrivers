-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Integration tests for lockUsers and lockCredentials commands with state
-- pre-configured before each test.  Two users and two credentials are seeded
-- at the start of every test so tests can focus on the various response states
-- produced by the z-wave response handlers in commands.lua.

local test              = require "integration_test"
local t_utils           = require "integration_test.utils"
local capabilities      = require "st.capabilities"
local zw                = require "st.zwave"
local table_utils       = require "lock_utils.tables"
local constants         = require "lock_utils.constants"
local Notification      = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local UserCode          = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
local access_control_event = Notification.event.access_control
local json              = require "st.json"


test.disable_startup_messages()
if table_utils.find_all_entries_by == nil then
  function table_utils.find_all_entries_by(device, table_name, key, value)
    local entries = table_utils.get_state(device, table_name) or {}
    local matches = {}
    for _, entry in ipairs(entries) do
      if entry[key] == value then table.insert(matches, entry) end
    end
    return matches
  end
end


-- ── Shared device ──────────────────────────────────────────────────────────

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

local function queue_user_code_added(user_identifier)
  test.socket.zwave:__queue_receive({ mock_device.id, Notification:Report({
    notification_type = Notification.notification_type.ACCESS_CONTROL,
    event = access_control_event.NEW_USER_CODE_ADDED,
    event_parameter = string.char(user_identifier),
  }) })
end

local function queue_user_code_deleted(user_identifier)
  test.socket.zwave:__queue_receive({ mock_device.id, Notification:Report({
    notification_type = Notification.notification_type.ACCESS_CONTROL,
    event = access_control_event.SINGLE_USER_CODE_DELETED,
    event_parameter = string.char(user_identifier),
  }) })
end

-- ── Seeding helpers ────────────────────────────────────────────────────────

local INITIAL_USERS = {
  { userIndex = 1, userName = "Alice", userType = "guest" },
  { userIndex = 2, userName = "Bob",   userType = "guest" },
}
local INITIAL_CREDS = {
  { userIndex = 1, credentialIndex = 1, credentialType = "pin" },
  { userIndex = 2, credentialIndex = 2, credentialType = "pin" },
}

-- Seed a list of entries into a named table, consuming the resulting events.
local function seed_table(attribute_fn, table_name, entries)
  local accumulated = {}
  for _, entry in ipairs(entries) do
    table.insert(accumulated, entry)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        attribute_fn(accumulated, { visibility = { displayed = false } }))
    )
    assert(
      table_utils.add_entry(mock_device, table_name, entry) == constants.COMMAND_RESULT.SUCCESS,
      "seed_table: add_entry failed for " .. table_name
    )
  end
  test.wait_for_events()
end

-- Pre-configure each test with 2 users and 2 credentials.
local function setup_state()
  seed_table(capabilities.lockUsers.users,            "users",       INITIAL_USERS)
  seed_table(capabilities.lockCredentials.credentials, "credentials", INITIAL_CREDS)
end

-- ============================================================================
-- addUser — pre-configured device (2 users already present)
-- ============================================================================

test.register_coroutine_test(
  "addUser (pre-configured): assigns the next available index (3) when two users already exist",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "addUser", args = { "Carol", "guest" } },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          {
            { userIndex = 1, userName = "Alice", userType = "guest" },
            { userIndex = 2, userName = "Bob",   userType = "guest" },
            { userIndex = 3, userName = "Carol",  userType = "guest" },
          },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 3 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- updateUser — pre-configured device
-- ============================================================================

test.register_coroutine_test(
  "updateUser (pre-configured): updates Alice's name and emits success with userIndex",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "updateUser", args = { 1, "AliceRenamed", "guest" } },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          {
            { userIndex = 1, userName = "AliceRenamed", userType = "guest" },
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
  "updateUser (pre-configured): returns failure for a userIndex that does not exist",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "updateUser", args = { 10, "Ghost", "guest" } },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          {
            { userIndex = 1, userName = "Alice", userType = "guest" },
            { userIndex = 2, userName = "Bob",   userType = "guest" },
            { userIndex = 10, userName = "Ghost", userType = "guest" },
          },
          { visibility = { displayed = false } }
        ))
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "updateUser", statusCode = "success", userIndex = 10 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- deleteUser with associated credential — exercises clear_pin_code_response
-- ============================================================================

test.register_coroutine_test(
  "deleteUser (pre-configured, PASS): removes both user and credential and emits success for each",
  function()
    setup_state()

    -- Delete user 1 who has credential 1 → driver injects deleteCredential → ClearPINCode
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "deleteUser", args = { 1 } },
    })
    expect_clear_pin_code(1)
    test.wait_for_events()

    queue_user_code_deleted(1)

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 2, userName = "Bob", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 2, credentialIndex = 2, credentialType = "pin" } },
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
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteCredential", statusCode = "success", credentialIndex = 1, userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- addCredential response states — set_pin_code_response
-- ============================================================================

test.register_coroutine_test(
  "addCredential (pre-configured): succeeds for a new slot and emits userIndex + credentialIndex",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 3, "guest", "pin", "pin03", "Guest 3" } },
    })

    expect_set_pin_code(3, "pin03")
    test.wait_for_events()

    queue_user_code_added(1)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          {
            { userIndex = 1, credentialIndex = 1, credentialType = "pin" },
            { userIndex = 2, credentialIndex = 2, credentialType = "pin" },
            { userIndex = 3, credentialIndex = 3, credentialType = "pin", credentialName = "Guest 3" },
          },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", userIndex = 3, credentialIndex = 3 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "addCredential (pre-configured): emits duplicate when the lock rejects with DUPLICATE_CODE",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 3, "guest", "pin", "pin01" } },
    })

    expect_set_pin_code(3, "pin01")
    test.wait_for_events()

    test.socket.zwave:__queue_receive({ mock_device.id, Notification:Report({ notification_type = Notification.notification_type.ACCESS_CONTROL, event = access_control_event.NEW_USER_CODE_NOT_ADDED_DUE_TO_DUPLICATE_CODE, event_parameter = string.char(1) }) })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "duplicate" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "addCredential (pre-configured): emits failure when the lock returns available",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 3, "guest", "pin", "pin03" } },
    })

    expect_set_pin_code(3, "pin03")
    test.wait_for_events()

    test.socket.zwave:__queue_receive({ mock_device.id, UserCode:Report({ user_identifier = 1, user_id_status = UserCode.user_id_status.AVAILABLE }) })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "failure" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- updateCredential response states — set_pin_code_response
-- ============================================================================

test.register_coroutine_test(
  "updateCredential (pre-configured): succeeds and emits success with userIndex and credentialIndex",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential",
        args = { 1, 1, "pin", "newPin1" } },
    })

    expect_set_pin_code(1, "newPin1")
    test.wait_for_events()

    queue_user_code_added(1)

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "updateCredential", statusCode = "success", userIndex = 1, credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "updateCredential (pre-configured): returns failure immediately for a non-existent credentialIndex",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential",
        args = { 99, 99, "pin", "badPin" } },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "updateCredential", statusCode = "failure" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- deleteCredential standalone (lockCredentials.DELETE path)
-- ============================================================================

test.register_coroutine_test(
  "deleteCredential (pre-configured, PASS): removes credential and emits success with indices",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential",
        args = { 1, "pin" } },
    })
    expect_clear_pin_code(1)
    test.wait_for_events()

    queue_user_code_deleted(1)

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 2, credentialIndex = 2, credentialType = "pin" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteCredential", statusCode = "success", credentialIndex = 1, userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.run_registered_tests()
