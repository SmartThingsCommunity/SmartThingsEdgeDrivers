-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Integration tests for the lockCredentials capability commands:
--   addCredential, updateCredential, deleteCredential, deleteAllCredentials

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

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("base-lock.yml"),
})
zigbee_test_utils.prepare_zigbee_env_info()

-- ── helpers ────────────────────────────────────────────────────────────────

local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

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
    assert(table_utils.add_entry(mock_device, "users", entry) == constants.COMMAND_RESULT.SUCCESS)
  end
  test.wait_for_events()
end

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
    assert(table_utils.add_entry(mock_device, "credentials", entry) == constants.COMMAND_RESULT.SUCCESS)
  end
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
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
        1, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "1234"),
    })
    test.wait_for_events()

    -- Lock responds with SUCCESS
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetPINCodeResponse.build_test_rx(mock_device, SetCodeStatus.SUCCESS),
    })

    -- Handler adds the credential and user to the credentials table
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1" } },
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
  "addCredential: emits failure when the lock returns GENERAL_FAILURE",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 1, "guest", "pin", "1234" } },
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
        1, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "1234"),
    })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetPINCodeResponse.build_test_rx(mock_device, SetCodeStatus.GENERAL_FAILURE),
    })

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

test.register_coroutine_test(
  "addCredential: emits resourceExhausted when the lock returns MEMORY_FULL",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 2, "guest", "pin", "5678" } },
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
        2, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "5678"),
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

test.register_coroutine_test(
  "addCredential: emits duplicate when the lock returns DUPLICATE_CODE",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 1, "guest", "pin", "1234" } },
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
        1, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "1234"),
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
  "addCredential: returns busy when another operation is already in progress",
  function()
    -- Put the device into busy state by starting an addCredential operation
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential",
        args = { 1, "guest", "pin", "1234" } },
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
        1, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "1234"),
    })
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
  "updateCredential: sends SetPINCode and emits success when the lock acknowledges",
  function()
    seed_credentials({ { userIndex = 1, credentialIndex = 1, credentialType = "pin" } })

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential",
        args = { 1, 1, "pin", "newPin9" } },
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
        1, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "newPin9"),
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
  "updateCredential: returns failure immediately when the credential does not exist in the table",
  function()
    -- No credentials seeded — credentialIndex 99 does not exist
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential",
        args = { 99, 99, "pin", "badPin" } },
    })

    -- No zigbee message should be sent
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
    seed_credentials({ { userIndex = 1, credentialIndex = 1, credentialType = "pin" } })

    -- Start first updateCredential to make device busy
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential",
        args = { 1, 1, "pin", "pin1111" } },
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
        1, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "pin1111"),
    })
    test.wait_for_events()

    -- Second updateCredential while first is pending
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
  "deleteCredential: sends ClearPINCode and emits success with indices when the lock returns PASS",
  function()
    seed_users({ { userIndex = 1, userName = "Alice", userType = "guest" } })
    seed_credentials({ { userIndex = 1, credentialIndex = 1, credentialType = "pin" } })

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

    -- credential table and user should be deleted
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials({}, { visibility = { displayed = false } }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users({}, { visibility = { displayed = false } }))
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
  "deleteCredential: emits failure when the lock returns FAIL",
  function()
    seed_credentials({ { userIndex = 1, credentialIndex = 1, credentialType = "pin" } })

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

test.register_coroutine_test(
  "deleteCredential: returns failure immediately when the credentialIndex does not exist in the table",
  function()
    -- No credentials seeded — index 5 is unknown
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential",
        args = { 5, "pin" } },
    })

    -- No zigbee messages should be sent
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
    seed_credentials({
      { userIndex = 1, credentialIndex = 1, credentialType = "pin" },
      { userIndex = 2, credentialIndex = 2, credentialType = "pin" },
    })

    -- Start first deleteCredential to make device busy
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential",
        args = { 1, "pin" } },
    })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.SendPINOverTheAir:write(mock_device, true) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearPINCode(mock_device, 1) })
    test.wait_for_events()

    -- Second deleteCredential while first is pending → busy
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteCredential",
        args = { 2, "pin" } },
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

    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearAllPINCodes(mock_device) })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.ClearAllPINCodesResponse.build_test_rx(mock_device, ResponseStatus.PASS),
    })

    -- deleteAllCredentials only clears credentials; users table is untouched
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
  "deleteAllCredentials: emits failure when the lock returns FAIL",
  function()
    seed_credentials({ { userIndex = 1, credentialIndex = 1, credentialType = "pin" } })

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

test.register_coroutine_test(
  "deleteAllCredentials: returns busy when another operation is already in progress",
  function()
    seed_credentials({ { userIndex = 1, credentialIndex = 1, credentialType = "pin" } })

    -- First deleteAllCredentials starts the zigbee flow (device is now busy)
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "deleteAllCredentials", args = {} },
    })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearAllPINCodes(mock_device) })
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
