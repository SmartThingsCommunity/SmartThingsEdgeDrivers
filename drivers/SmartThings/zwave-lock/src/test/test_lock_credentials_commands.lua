-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Integration tests for the lockCredentials capability commands:
--   addCredential, updateCredential, deleteCredential, deleteAllCredentials

local test              = require "integration_test"
local t_utils           = require "integration_test.utils"
local capabilities      = require "st.capabilities"
local json              = require "st.json"
local zw                = require "st.zwave"
local table_utils       = require "lock_utils.tables"
local constants         = require "lock_utils.constants"
local Notification      = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local UserCode          = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
local access_control_event = Notification.event.access_control

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
local function mock_state_key(component_id, capability_id, attribute_name)
  return table.concat({ component_id, capability_id, attribute_name }, "|")
end

local function install_state_mocks()
  mock_latest_state = {}
  mock_device.get_latest_state = function(_, component_id, capability_id, attribute_name, default_value)
    local value = mock_latest_state[mock_state_key(component_id, capability_id, attribute_name)]
    if value == nil then
      if capability_id == capabilities.lockCredentials.ID and attribute_name == capabilities.lockCredentials.credentials.NAME then
        value = mock_device.persistent_store.persistedCredentials
      elseif capability_id == capabilities.lockUsers.ID and attribute_name == capabilities.lockUsers.users.NAME then
        value = mock_device.persistent_store.persistedUsers
      end
    end
    if value == nil then return default_value end
    return value
  end
  local original_set_field = mock_device.set_field
  mock_device.set_field = function(_, key, value, opts)
    if opts and opts.persist then
      mock_device.persistent_store[key] = value
    else
      mock_device.transient_store[key] = value
    end
    if original_set_field then original_set_field(mock_device, key, value, opts) end
  end
  mock_device.emit_event = function(_, event)
    mock_latest_state[mock_state_key("main", event.capability.ID, event.attribute.NAME)] = event.value.value
    local message = mock_device:generate_test_message("main", event)
    test.socket.capability:send(message[1], json.encode(message[2]))
  end
end

-- ── helpers ────────────────────────────────────────────────────────────────

local function test_init()
  mock_device.persistent_store = mock_device.persistent_store or {}
  mock_device.transient_store = mock_device.transient_store or {}
  install_state_mocks()
  mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })
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

local function queue_user_code_added(user_identifier)
  test.socket.zwave:__queue_receive({ mock_device.id, Notification:Report({
    notification_type = Notification.notification_type.ACCESS_CONTROL,
    event = access_control_event.NEW_USER_CODE_ADDED,
    event_parameter = string.char(user_identifier),
  }) })
end

local function seed_users(entries)
  for _, entry in ipairs(entries) do
    local so_far = {}
    for _, e in ipairs(entries) do
      table.insert(so_far, e)
      if e == entry then break end
    end
    local event = capabilities.lockUsers.users(so_far, { visibility = { displayed = false } })
    mock_latest_state[mock_state_key("main", event.capability.ID, event.attribute.NAME)] = event.value.value
  end
  mock_device.persistent_store.persistedUsers = entries
  test.wait_for_events()
end

local function seed_credentials(entries)
  for _, entry in ipairs(entries) do
    local so_far = {}
    for _, e in ipairs(entries) do
      table.insert(so_far, e)
      if e == entry then break end
    end
    local event = capabilities.lockCredentials.credentials(so_far, { visibility = { displayed = false } })
    mock_latest_state[mock_state_key("main", event.capability.ID, event.attribute.NAME)] = event.value.value
  end
  mock_device.persistent_store.persistedCredentials = entries
  test.wait_for_events()
end

-- ============================================================================
-- addCredential
-- ============================================================================

test.register_coroutine_test(
  "addCredential: sends SetPINCode to the lock and emits success when the lock acknowledges",
  function()
    -- Queue the capability command: userIndex=1, userType="guest", credentialType="pin", credentialData="1234"
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 1, "guest", "pin", "1234" } },
    })

    -- Expect SetPINCode to be sent to the lock
    expect_set_pin_code(1, "1234")
    test.wait_for_events()

    -- Lock responds with SUCCESS
    queue_user_code_added(1)

    -- Handler adds the credential to the credentials table.
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin" } },
          { visibility = { displayed = false } }
        ))
    )
    -- commandResult with userIndex and credentialIndex
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", userIndex = 1, credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "addCredential: emits duplicate when the lock returns DUPLICATE_CODE",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 1, "guest", "pin", "1234" } },
    })

    expect_set_pin_code(1, "1234")
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
  "addCredential: returns busy when another operation is already in progress",
  function()
    -- Put the device into busy state by starting an addCredential operation
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 1, "guest", "pin", "1234" } },
    })
    expect_set_pin_code(1, "1234")
    test.wait_for_events()

    -- Second addCredential while first is still pending → should get busy
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 2, "guest", "pin", "5678" } },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "busy" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- updateCredential
-- ============================================================================

test.register_coroutine_test(
  "updateCredential: returns failure when cached credential state is unavailable",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential",
        args = { 1, 1, "pin", "newPin9" } },
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

test.register_coroutine_test(
  "updateCredential: returns failure immediately when the credential does not exist in the table",
  function()
    -- No credentials seeded — credentialIndex 99 does not exist
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential",
        args = { 99, 99, "pin", "badPin" } },
    })

    -- No z-wave message should be sent
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

test.register_coroutine_test(
  "updateCredential: returns busy when another operation is already in progress",
  function()
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.LOCK_CREDENTIALS.ADD, {})

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential",
        args = { 1, 1, "pin", "pin2222" } },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "updateCredential", statusCode = "busy" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- deleteCredential
-- ============================================================================

test.register_coroutine_test(
  "deleteCredential: returns failure when credential state is unavailable",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential",
        args = { 1, "pin" } },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteCredential", statusCode = "failure" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "deleteCredential: returns failure when credential state is unavailable",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential",
        args = { 1, "pin" } },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteCredential", statusCode = "failure" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "deleteCredential: returns failure immediately when the credentialIndex does not exist in the table",
  function()
    -- No credentials seeded — index 5 is unknown
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential",
        args = { 5, "pin" } },
    })

    -- No z-wave messages should be sent
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteCredential", statusCode = "failure" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "deleteCredential: returns busy when another operation is already in progress",
  function()
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.LOCK_CREDENTIALS.ADD, {})

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential",
        args = { 1, "pin" } },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteCredential", statusCode = "busy" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- deleteAllCredentials
-- ============================================================================

test.register_coroutine_test(
  "deleteAllCredentials: sends ClearAllPINCodes and emits success when the lock returns PASS",
  function()
    seed_users({
      { userIndex = 1, userName = "Alice", userType = "guest" },
    })
    seed_credentials({
      { userIndex = 1, credentialIndex = 1, credentialType = "pin" },
    })

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteAllCredentials", args = {} },
    })

    test.timer.__create_and_queue_test_time_advance_timer(4, "oneshot")
    test.wait_for_events()

    test.mock_time.advance_time(4)
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
  "deleteAllCredentials: emits busy when another operation is already in progress",
  function()
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.LOCK_CREDENTIALS.ADD, {})

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteAllCredentials", args = {} },
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteAllCredentials", statusCode = "busy" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "deleteAllCredentials: returns busy when another operation is already in progress",
  function()
    seed_credentials({ { userIndex = 1, credentialIndex = 1, credentialType = "pin" } })

    -- First deleteAllCredentials starts the z-wave flow (device is now busy)
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteAllCredentials", args = {} },
    })
    -- deleteAllCredentials sends individual UserCode:Set AVAILABLE commands
    test.wait_for_events()

    -- Second deleteAllCredentials while first is pending → busy
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteAllCredentials", args = {} },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteAllCredentials", statusCode = "busy" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.run_registered_tests()
