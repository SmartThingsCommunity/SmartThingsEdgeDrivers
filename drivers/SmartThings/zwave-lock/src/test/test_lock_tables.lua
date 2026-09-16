-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Unit tests for lock_utils/tables.lua
-- Tests directly call table_utils functions and verify both return values
-- and emitted capability events.

local test        = require "integration_test"
local t_utils     = require "integration_test.utils"
local json         = require "st.json"
local capabilities = require "st.capabilities"
local st_utils = require "st.utils"
local table_utils  = require "lock_utils.tables"
local constants    = require "lock_utils.constants"

test.disable_startup_messages()

-- ---------------------------------------------------------------------------
-- Shared mock device
-- ---------------------------------------------------------------------------

local zw = require "st.zwave"

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

local mock_latest_state = {}
local mock_persistent_fields = {}
local mock_transient_fields = {}

local function mock_state_key(component_id, capability_id, attribute_name)
  return table.concat({ component_id, capability_id, attribute_name }, "|")
end

local function install_table_utils_device_mocks()
  mock_latest_state = {}
  mock_persistent_fields = {}
  mock_transient_fields = {}
  mock_device.supports_capability = function() return true end
  mock_device.log = { error = function() end, warn = function() end }
  mock_device.get_latest_state = function(_, component_id, capability_id, attribute_name, default_value)
    local value = mock_latest_state[mock_state_key(component_id, capability_id, attribute_name)]
    if value == nil then return default_value end
    return value
  end
  mock_device.emit_event = function(_, event)
    mock_latest_state[mock_state_key("main", event.capability.ID, event.attribute.NAME)] = event.value.value
    local message = mock_device:generate_test_message("main", event)
    test.socket.capability:send(message[1], json.encode(message[2]))
  end
  mock_device.set_field = function(_, key, value, opts)
    if opts and opts.persist then
      mock_persistent_fields[key] = value
    else
      mock_transient_fields[key] = value
    end
  end
  mock_device.get_field = function(_, key)
    if mock_transient_fields[key] ~= nil then return mock_transient_fields[key] end
    return mock_persistent_fields[key]
  end
  -- tables.lua calls device.log.{debug,warn,error} unconditionally.
  rawset(mock_device, "log", {
    debug = function() end,
    info  = function() end,
    warn  = function() end,
    error = function() end,
  })
end


local function test_init()
  test.mock_device.add_test_device(mock_device)
  install_table_utils_device_mocks()
end
test.set_test_init_function(test_init)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Seed the users table with `entries` and consume the resulting emit_events.
-- After this call the state cache has those entries and the socket is clean.
local function seed_users(entries)
  for _, entry in ipairs(entries) do
    -- Build the expected post-insert table up to this entry.
    local expected = {}
    for _, e in ipairs(entries) do
      table.insert(expected, e)
      if e == entry then break end
    end
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(expected, { visibility = { displayed = false } }))
    )
    local result = table_utils.add_entry(mock_device, "users", entry)
    assert(result == constants.COMMAND_RESULT.SUCCESS,
      "seed_users: add_entry failed for entry userIndex=" .. tostring(entry.userIndex))
  end
end

-- Seed the credentials table with `entries` and consume the resulting emit_events.
local function seed_credentials(entries)
  for _, entry in ipairs(entries) do
    local expected = {}
    for _, e in ipairs(entries) do
      table.insert(expected, e)
      if e == entry then break end
    end
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(expected, { visibility = { displayed = false } }))
    )
    local result = table_utils.add_entry(mock_device, "credentials", entry)
    assert(result == constants.COMMAND_RESULT.SUCCESS,
      "seed_credentials: add_entry failed for entry credentialIndex=" .. tostring(entry.credentialIndex))
  end
end

-- ===========================================================================
-- add_entry
-- ===========================================================================

test.register_coroutine_test(
  "add_entry: adds a new user entry and emits the updated table",
  function()
    local entry = { userIndex = 1, userType = "guest", userName = "Alice" }

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users({ entry }, { visibility = { displayed = false } }))
    )

    local result = table_utils.add_entry(mock_device, "users", entry)
    assert(result == constants.COMMAND_RESULT.SUCCESS,
      "Expected SUCCESS, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "add_entry: returns OCCUPIED when an entry with the same userIndex already exists",
  function()
    local entry = { userIndex = 1, userType = "guest", userName = "Alice" }
    seed_users({ entry })

    -- Attempt to add a different entry with the same userIndex (match_key)
    local duplicate = { userIndex = 1, userType = "unrestricted", userName = "Bob" }
    local result = table_utils.add_entry(mock_device, "users", duplicate)
    assert(result == constants.COMMAND_RESULT.OCCUPIED,
      "Expected OCCUPIED, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "add_entry: returns RESOURCE_EXHAUSTED when table is at max capacity",
  function()
    local entries = {}
    for i = 1, 20 do
      entries[i] = { userIndex = i, userType = "guest", userName = "User" .. i }
    end
    seed_users(entries)

    local overflow = { userIndex = 21, userType = "guest", userName = "Overflow" }
    local result = table_utils.add_entry(mock_device, "users", overflow)
    assert(result == constants.COMMAND_RESULT.RESOURCE_EXHAUSTED,
      "Expected RESOURCE_EXHAUSTED, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "add_entry: returns FAILURE when a required key is missing",
  function()
    -- userType is required for users table
    local incomplete = { userIndex = 1 }
    local result = table_utils.add_entry(mock_device, "users", incomplete)
    assert(result == constants.COMMAND_RESULT.FAILURE,
      "Expected FAILURE, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "add_entry: returns FAILURE for an unknown table name",
  function()
    local result = table_utils.add_entry(mock_device, "nonexistent_table",
      { userIndex = 1, userType = "guest" })
    assert(result == constants.COMMAND_RESULT.FAILURE,
      "Expected FAILURE, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "add_entry: adds a credential entry and emits updated credentials table",
  function()
    local entry = { userIndex = 1, credentialIndex = 1, credentialType = "pin" }

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials({ entry }, { visibility = { displayed = false } }))
    )

    local result = table_utils.add_entry(mock_device, "credentials", entry)
    assert(result == constants.COMMAND_RESULT.SUCCESS,
      "Expected SUCCESS, got: " .. tostring(result))
  end
)

-- ===========================================================================
-- update_entry
-- ===========================================================================

test.register_coroutine_test(
  "update_entry: updates an existing user entry and emits updated table",
  function()
    local original = { userIndex = 1, userType = "guest", userName = "Alice" }
    seed_users({ original })

    local expected_after_update = {
      { userIndex = 1, userType = "adminMember", userName = "Alice_Updated" }
    }
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(expected_after_update, { visibility = { displayed = false } }))
    )

    local result = table_utils.update_entry(mock_device, "users", 1,
      { userName = "Alice_Updated", userType = "adminMember" })
    assert(result == constants.COMMAND_RESULT.SUCCESS,
      "Expected SUCCESS, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "update_entry: returns FAILURE when no entry matches the match_key value",
  function()
    local result = table_utils.update_entry(mock_device, "users", 99,
      { userName = "Ghost" })
    assert(result == constants.COMMAND_RESULT.FAILURE,
      "Expected FAILURE, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "update_entry: only updates the specified fields, leaves others intact",
  function()
    local entry1 = { userIndex = 1, userType = "guest", userName = "Alice" }
    local entry2 = { userIndex = 2, userType = "guest", userName = "Bob" }
    seed_users({ entry1, entry2 })

    -- Update only userName of entry 2; userType should remain "guest"
    local expected = {
      { userIndex = 1, userType = "guest", userName = "Alice" },
      { userIndex = 2, userType = "guest", userName = "Bob_Renamed" },
    }
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(expected, { visibility = { displayed = false } }))
    )

    local result = table_utils.update_entry(mock_device, "users", 2, { userName = "Bob_Renamed" })
    assert(result == constants.COMMAND_RESULT.SUCCESS,
      "Expected SUCCESS, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "update_entry: returns FAILURE for an unknown table name",
  function()
    local result = table_utils.update_entry(mock_device, "bad_table", 1, { userName = "X" })
    assert(result == constants.COMMAND_RESULT.FAILURE,
      "Expected FAILURE, got: " .. tostring(result))
  end
)

-- ===========================================================================
-- delete_entry
-- ===========================================================================

test.register_coroutine_test(
  "delete_entry: deletes an existing entry and returns COMMAND_RESULT.SUCCESS",
  function()
    local entry = { userIndex = 1, userType = "guest", userName = "Alice" }
    seed_users({ entry })

    -- After deletion the table is empty
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users({}, { visibility = { displayed = false } }))
    )

    local result = table_utils.delete_entry(mock_device, "users", 1)
    assert(result == constants.COMMAND_RESULT.SUCCESS,
      "Expected SUCCESS, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "delete_entry: returns FAILURE when no entry matches the match_key value",
  function()
    local result = table_utils.delete_entry(mock_device, "users", 99)
    assert(result == constants.COMMAND_RESULT.FAILURE,
      "Expected FAILURE, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "delete_entry: remaining entries are intact after a deletion",
  function()
    local e1 = { userIndex = 1, userType = "guest", userName = "Alice" }
    local e2 = { userIndex = 2, userType = "guest", userName = "Bob" }
    local e3 = { userIndex = 3, userType = "guest", userName = "Carol" }
    seed_users({ e1, e2, e3 })

    -- Delete the middle entry; expect e1 and e3 remain
    local expected_remaining = {
      { userIndex = 1, userType = "guest", userName = "Alice" },
      { userIndex = 3, userType = "guest", userName = "Carol" },
    }
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(expected_remaining, { visibility = { displayed = false } }))
    )

    local result = table_utils.delete_entry(mock_device, "users", 2)
    assert(result == constants.COMMAND_RESULT.SUCCESS,
      "Expected SUCCESS, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "delete_entry: returns FAILURE for an unknown table name",
  function()
    local result = table_utils.delete_entry(mock_device, "bad_table", 1)
    assert(result == constants.COMMAND_RESULT.FAILURE,
      "Expected FAILURE, got: " .. tostring(result))
  end
)

-- ===========================================================================
-- delete_all_entries
-- ===========================================================================

test.register_coroutine_test(
  "delete_all_entries: emits an empty users table and returns SUCCESS",
  function()
    local e1 = { userIndex = 1, userType = "guest", userName = "Alice" }
    local e2 = { userIndex = 2, userType = "guest", userName = "Bob" }
    seed_users({ e1, e2 })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users({}, { visibility = { displayed = false } }))
    )

    local result = table_utils.delete_all_entries(mock_device, "users")
    assert(result == constants.COMMAND_RESULT.SUCCESS,
      "Expected SUCCESS, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "delete_all_entries: returns SUCCESS even when the table is already empty",
  function()
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users({}, { visibility = { displayed = false } }))
    )

    local result = table_utils.delete_all_entries(mock_device, "users")
    assert(result == constants.COMMAND_RESULT.SUCCESS,
      "Expected SUCCESS, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "delete_all_entries: returns FAILURE for an unknown table name",
  function()
    local result = table_utils.delete_all_entries(mock_device, "bad_table")
    assert(result == constants.COMMAND_RESULT.FAILURE,
      "Expected FAILURE, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "delete_all_entries: emits an empty credentials table and returns SUCCESS",
  function()
    local cred = { userIndex = 1, credentialIndex = 1, credentialType = "pin" }
    seed_credentials({ cred })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials({}, { visibility = { displayed = false } }))
    )

    local result = table_utils.delete_all_entries(mock_device, "credentials")
    assert(result == constants.COMMAND_RESULT.SUCCESS,
      "Expected SUCCESS, got: " .. tostring(result))
  end
)

-- ===========================================================================
-- find_entry
-- ===========================================================================

test.register_coroutine_test(
  "find_entry: returns the matching entry when it exists",
  function()
    local e1 = { userIndex = 1, userType = "guest", userName = "Alice" }
    local e2 = { userIndex = 2, userType = "guest", userName = "Bob" }
    seed_users({ e1, e2 })

    local result = table_utils.find_entry(mock_device, "users", 2)
    assert(type(result) == "table",
      "Expected a table entry, got: " .. tostring(result))
    assert(result.userIndex == 2,
      "Expected userIndex == 2, got: " .. tostring(result.userIndex))
    assert(result.userName == "Bob",
      "Expected userName == 'Bob', got: " .. tostring(result.userName))
  end
)

test.register_coroutine_test(
  "find_entry: returns nil when no entry matches the value",
  function()
    local e1 = { userIndex = 1, userType = "guest", userName = "Alice" }
    seed_users({ e1 })

    local result = table_utils.find_entry(mock_device, "users", 99)
    assert(result == nil,
      "Expected nil for missing entry, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "find_entry: finds a credential entry by credentialIndex",
  function()
    local cred = { userIndex = 1, credentialIndex = 5, credentialType = "pin" }
    seed_credentials({ cred })

    local result = table_utils.find_entry(mock_device, "credentials", 5)
    assert(type(result) == "table",
      "Expected a table entry, got: " .. tostring(result))
    assert(result.credentialIndex == 5,
      "Expected credentialIndex == 5, got: " .. tostring(result.credentialIndex))
  end
)

-- ===========================================================================
-- find_entry_by
-- ===========================================================================

test.register_coroutine_test(
  "find_entry_by: returns the entry matching an arbitrary key",
  function()
    local e1 = { userIndex = 1, userType = "guest",        userName = "Alice" }
    local e2 = { userIndex = 2, userType = "adminMember",  userName = "Bob"   }
    seed_users({ e1, e2 })

    local result = table_utils.find_entry_by(mock_device, "users", "userName", "Bob")
    assert(type(result) == "table",
      "Expected a table entry, got: " .. tostring(result))
    assert(result.userIndex == 2,
      "Expected userIndex == 2, got: " .. tostring(result.userIndex))
  end
)

test.register_coroutine_test(
  "find_entry_by: returns nil when no entry matches",
  function()
    local e1 = { userIndex = 1, userType = "guest", userName = "Alice" }
    seed_users({ e1 })

    local result = table_utils.find_entry_by(mock_device, "users", "userName", "Nobody")
    assert(result == nil,
      "Expected nil for unmatched key/value, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "find_entry_by: returns the first matching entry when multiple entries share the same value",
  function()
    local e1 = { userIndex = 1, userType = "guest", userName = "Alice" }
    local e2 = { userIndex = 2, userType = "guest", userName = "Bob"   }
    local e3 = { userIndex = 3, userType = "guest", userName = "Carol" }
    seed_users({ e1, e2, e3 })

    local result = table_utils.find_entry_by(mock_device, "users", "userType", "guest")
    assert(type(result) == "table",
      "Expected a table entry, got: " .. tostring(result))
    assert(result.userIndex == 1,
      "Expected first match userIndex == 1, got: " .. tostring(result.userIndex))
  end
)

-- ===========================================================================
-- next_index
-- ===========================================================================

test.register_coroutine_test(
  "next_index: returns 1 when the table is empty",
  function()
    local result = table_utils.next_index(mock_device, "users")
    assert(result == 1,
      "Expected 1 for empty table, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "next_index: returns the next sequential index after a contiguous range",
  function()
    local entries = {}
    for i = 1, 3 do
      entries[i] = { userIndex = i, userType = "guest", userName = "User" .. i }
    end
    seed_users(entries)

    local result = table_utils.next_index(mock_device, "users")
    assert(result == 4,
      "Expected 4 after indices 1-3, got: " .. tostring(result))
  end
)

-- this should not happen during normal operation.
test.register_coroutine_test(
  "next_index: returns the lowest gap when indices are non-contiguous",
  function()
    -- Insert entries at indices 1 and 3, leaving a gap at 2
    local e1 = { userIndex = 1, userType = "guest", userName = "Alice" }
    local e3 = { userIndex = 3, userType = "guest", userName = "Carol" }
    seed_users({ e1, e3 })

    local result = table_utils.next_index(mock_device, "users")
    assert(result == 2,
      "Expected 2 as the lowest gap, got: " .. tostring(result))
  end
)

-- ===========================================================================
-- get_max_entries
-- ===========================================================================

test.register_coroutine_test(
  "get_max_entries: returns the default of 20 when the attribute is not set",
  function()
    local result = table_utils.get_max_entries(mock_device, "users")
    assert(result == 20,
      "Expected default max of 20, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "get_max_entries: returns the default of 20 for the credentials table when the attribute is not set",
  function()
    local result = table_utils.get_max_entries(mock_device, "credentials")
    assert(result == 20,
      "Expected default max of 20, got: " .. tostring(result))
  end
)

-- ===========================================================================
-- Persistence — mutations write to the persistent store
-- ===========================================================================

test.register_coroutine_test(
  "persist: add_entry writes the new users table to the persistent store immediately",
  function()
    local entry = { userIndex = 1, userType = "guest", userName = "Alice" }
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users({ entry }, { visibility = { displayed = false } }))
    )
    table_utils.add_entry(mock_device, "users", entry)

    local persisted = st_utils.deep_copy(mock_device:get_field("persistedUsers"))
    assert(type(persisted) == "table" and #persisted == 1,
      "Expected 1 persisted user, got: " .. tostring(persisted and #persisted))
    assert(persisted[1].userIndex == 1 and persisted[1].userName == "Alice",
      "Persisted user data does not match the added entry")
  end
)

test.register_coroutine_test(
  "persist: update_entry writes the updated users table to the persistent store immediately",
  function()
    local entry = { userIndex = 1, userType = "guest", userName = "Alice" }
    seed_users({ entry })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userType = "adminMember", userName = "Alice" } },
          { visibility = { displayed = false } }))
    )
    table_utils.update_entry(mock_device, "users", 1, { userType = "adminMember" })

    local persisted = st_utils.deep_copy(mock_device:get_field("persistedUsers"))
    assert(type(persisted) == "table" and #persisted == 1,
      "Expected 1 persisted user after update")
    assert(persisted[1].userType == "adminMember",
      "Persisted user type was not updated, got: " .. tostring(persisted[1].userType))
  end
)

test.register_coroutine_test(
  "persist: delete_entry removes the entry from the persistent store immediately",
  function()
    local e1 = { userIndex = 1, userType = "guest", userName = "Alice" }
    local e2 = { userIndex = 2, userType = "guest", userName = "Bob" }
    seed_users({ e1, e2 })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users({ e2 }, { visibility = { displayed = false } }))
    )
    table_utils.delete_entry(mock_device, "users", 1)

    local persisted = st_utils.deep_copy(mock_device:get_field("persistedUsers"))
    assert(type(persisted) == "table" and #persisted == 1,
      "Expected 1 persisted user after delete, got: " .. tostring(persisted and #persisted))
    assert(persisted[1].userIndex == 2,
      "Expected remaining user to have userIndex == 2, got: " .. tostring(persisted[1].userIndex))
  end
)

test.register_coroutine_test(
  "persist: delete_all_entries writes an empty table to the persistent store",
  function()
    local entry = { userIndex = 1, userType = "guest", userName = "Alice" }
    seed_users({ entry })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users({}, { visibility = { displayed = false } }))
    )
    table_utils.delete_all_entries(mock_device, "users")

    local persisted = st_utils.deep_copy(mock_device:get_field("persistedUsers"))
    assert(type(persisted) == "table" and #persisted == 0,
      "Expected empty persistent store after delete_all, got: " .. tostring(persisted and #persisted))
  end
)

test.register_coroutine_test(
  "persist: add_entry writes the new credentials table to the persistent store immediately",
  function()
    local cred = { userIndex = 1, credentialIndex = 1, credentialType = "pin" }
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials({ cred }, { visibility = { displayed = false } }))
    )
    table_utils.add_entry(mock_device, "credentials", cred)

    local persisted = st_utils.deep_copy(mock_device:get_field("persistedCredentials"))
    assert(type(persisted) == "table" and #persisted == 1,
      "Expected 1 persisted credential, got: " .. tostring(persisted and #persisted))
    assert(persisted[1].credentialIndex == 1,
      "Persisted credential index does not match")
  end
)

-- ===========================================================================
-- Persistence — get_state falls back to the persistent store
-- ===========================================================================

test.register_coroutine_test(
  "persist: get_state returns data from the persistent store when capability state cache is absent",
  function()
    -- The device was loaded with a pre-seeded persistent field (set in test_init
    -- below), but no capability event has been emitted for users, so get_latest_state
    -- returns nil.  get_state must fall back to the persistent store.
    local state = table_utils.get_state(mock_device, "users")
    assert(type(state) == "table" and #state == 1,
      "Expected 1 user from persistent-store fallback, got: " .. tostring(state and #state))
    assert(state[1].userIndex == 1 and state[1].userName == "Alice",
      "Fallback data does not match pre-seeded persistent entry")
  end,
  {
    test_init = function()
      -- Pre-seed persistent store BEFORE add_test_device so that wrapped_init
      -- copies the field into the device's persistent_store on startup.
      mock_device:set_field(
        "persistedUsers",
        { { userIndex = 1, userType = "guest", userName = "Alice" } },
        { persist = true }
      )
      test.mock_device.add_test_device(mock_device)
    end,
  }
)

-- ===========================================================================
-- Persistence — restore_from_persistent_store re-emits stored tables
-- ===========================================================================

test.register_coroutine_test(
  "persist: restore_from_persistent_store emits users capability event for stored data",
  function()
    local user = { userIndex = 1, userType = "guest", userName = "Alice" }
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users({ user }, { visibility = { displayed = false } }))
    )
    table_utils.restore_from_persistent_store(mock_device)
  end,
  {
    test_init = function()
      install_table_utils_device_mocks()
      mock_device:set_field(
        "persistedUsers",
        { { userIndex = 1, userType = "guest", userName = "Alice" } },
        { persist = true }
      )
      test.mock_device.add_test_device(mock_device)
    end,
  }
)

test.register_coroutine_test(
  "persist: restore_from_persistent_store emits credentials capability event for stored data",
  function()
    local cred = { userIndex = 1, credentialIndex = 1, credentialType = "pin" }
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials({ cred }, { visibility = { displayed = false } }))
    )
    table_utils.restore_from_persistent_store(mock_device)
  end,
  {
    test_init = function()
      install_table_utils_device_mocks()
      mock_device:set_field(
        "persistedCredentials",
        { { userIndex = 1, credentialIndex = 1, credentialType = "pin" } },
        { persist = true }
      )
      test.mock_device.add_test_device(mock_device)
    end,
  }
)

test.register_coroutine_test(
  "persist: restore_from_persistent_store is a no-op when the persistent store is empty",
  function()
    -- No capability events expected when there is nothing in the persistent store.
    table_utils.restore_from_persistent_store(mock_device)
  end
)

test.run_registered_tests()
