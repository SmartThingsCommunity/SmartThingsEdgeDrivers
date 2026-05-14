-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Integration tests for lockUsers and lockCredentials commands with state
-- pre-configured before each test.  Two users and two credentials are seeded
-- at the start of every test so tests can focus on the various response states
-- produced by the zigbee response handlers in commands.lua.

local test              = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils           = require "integration_test.utils"
local capabilities      = require "st.capabilities"
local clusters          = require "st.zigbee.zcl.clusters"
local DoorLock          = clusters.DoorLock
local table_utils       = require "lock_utils.tables"
local constants         = require "lock_utils.constants"

local DoorLockUserStatus = DoorLock.types.DrlkUserStatus
local DoorLockUserType   = DoorLock.types.DrlkUserType
local SetCodeStatus      = DoorLock.types.DrlkSetCodeStatus
local ResponseStatus     = DoorLock.types.DrlkPassFailStatus

-- ── Shared device ──────────────────────────────────────────────────────────

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("base-lock.yml"),
})
zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

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
        capabilities.lockUsers.commandResult(
          { commandName = "updateUser", statusCode = "failure" },
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

    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.SendPINOverTheAir:write(mock_device, true) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearPINCode(mock_device, 1) })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.ClearPINCodeResponse.build_test_rx(mock_device, ResponseStatus.PASS),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 2, credentialIndex = 2, credentialType = "pin" } },
          { visibility = { displayed = false } }
        ))
    )
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

test.register_coroutine_test(
  "deleteUser (pre-configured, FAIL): emits failure for both capabilities when the lock rejects",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "deleteUser", args = { 2 } },
    })

    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.SendPINOverTheAir:write(mock_device, true) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearPINCode(mock_device, 2) })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.ClearPINCodeResponse.build_test_rx(mock_device, ResponseStatus.FAIL),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "deleteUser", statusCode = "failure" },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
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
        args = { 3, "guest", "pin", "pin03" } },
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
        3, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "pin03"),
    })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetPINCodeResponse.build_test_rx(mock_device, SetCodeStatus.SUCCESS),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          {
            { userIndex = 1, userName = "Alice", userType = "guest" },
            { userIndex = 2, userName = "Bob",   userType = "guest" },
            { userIndex = 3, userName = "Guest 3", userType = "guest" }, -- default name since lock doesn't provide one
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

    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
        3, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "pin01"),
    })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetPINCodeResponse.build_test_rx(mock_device, SetCodeStatus.DUPLICATE_CODE),
    })

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
  "addCredential (pre-configured): emits resourceExhausted when the lock returns MEMORY_FULL",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 3, "guest", "pin", "pin03" } },
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
        3, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "pin03"),
    })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetPINCodeResponse.build_test_rx(mock_device, SetCodeStatus.MEMORY_FULL),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "resourceExhausted" },
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

    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
        1, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "newPin1"),
    })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetPINCodeResponse.build_test_rx(mock_device, SetCodeStatus.SUCCESS),
    })

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

    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.SendPINOverTheAir:write(mock_device, true) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearPINCode(mock_device, 1) })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.ClearPINCodeResponse.build_test_rx(mock_device, ResponseStatus.PASS),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 2, credentialIndex = 2, credentialType = "pin" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 2, userName = "Bob", userType = "guest" } },
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

test.register_coroutine_test(
  "deleteCredential (pre-configured, FAIL): emits failure when the lock rejects the clear",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential",
        args = { 2, "pin" } },
    })

    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.SendPINOverTheAir:write(mock_device, true) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearPINCode(mock_device, 2) })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.ClearPINCodeResponse.build_test_rx(mock_device, ResponseStatus.FAIL),
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

-- ============================================================================
-- deleteAllCredentials standalone (lockCredentials.DELETE_ALL path)
-- ============================================================================

test.register_coroutine_test(
  "deleteAllCredentials (pre-configured, PASS): clears only credentials and emits success",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteAllCredentials", args = {} },
    })

    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearAllPINCodes(mock_device) })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.ClearAllPINCodesResponse.build_test_rx(mock_device, ResponseStatus.PASS),
    })

    -- Only credentials table is cleared; users table is untouched (no lockUsers.users event)
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
  "deleteAllCredentials (pre-configured, FAIL): emits failure and leaves tables unchanged",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteAllCredentials", args = {} },
    })

    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearAllPINCodes(mock_device) })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.ClearAllPINCodesResponse.build_test_rx(mock_device, ResponseStatus.FAIL),
    })

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
-- deleteAllUsers (lockUsers.DELETE_ALL path — clears both tables)
-- ============================================================================

test.register_coroutine_test(
  "deleteAllUsers (pre-configured, PASS): clears both tables and emits success for both capabilities",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "deleteAllUsers", args = {} },
    })

    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearAllPINCodes(mock_device) })
    test.wait_for_events()

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
  "deleteAllUsers (pre-configured, FAIL): emits failure for both capabilities when the lock rejects",
  function()
    setup_state()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "deleteAllUsers", args = {} },
    })

    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearAllPINCodes(mock_device) })
    test.wait_for_events()

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

test.run_registered_tests()
