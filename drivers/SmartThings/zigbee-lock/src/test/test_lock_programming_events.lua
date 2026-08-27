-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Tests for the ProgrammingEventNotification handler in lock_handlers/zigbee_responses.lua.
--
-- Cases covered:
--   • PIN_CODE_ADDED   received while NOT busy (manual addition at the lock)
--   • PIN_CODE_DELETED received while NOT busy (manual deletion at the lock)
--   • PIN_CODE_CHANGED received while NOT busy (manual update — not currently handled)
--   • PIN_CODE_ADDED   while addCredential in flight with matching user (failsafe path)
--   • PIN_CODE_CHANGED while updateCredential in flight with matching user (failsafe path)
--   • PIN_CODE_DELETED while deleteCredential in flight with matching user (failsafe path)
--   • PIN_CODE_ADDED   while busy with DIFFERENT user (processed as manual event)
--   • PIN_CODE_DELETED while busy with DIFFERENT user (processed as manual event)
--   • PIN_CODE_ADDED   received after BUSY ends (late notification from our SetPINCode; credential
--                       not double-added)
--   • PIN_CODE_ADDED   received after BUSY ends (both entries already exist; complete no-op)
--   • PIN_CODE_DELETED received after BUSY ends (late notification from our ClearPINCode; credential
--                       already deleted)
--   • PIN_CODE_CHANGED received after BUSY ends (late notification from our SetPINCode update;
--                       not handled, no effect)

local test              = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils           = require "integration_test.utils"

local clusters      = require "st.zigbee.zcl.clusters"
local DoorLock      = clusters.DoorLock
local capabilities  = require "st.capabilities"
local constants     = require "lock_utils.constants"

local DoorLockUserStatus   = DoorLock.types.DrlkUserStatus
local DoorLockUserType     = DoorLock.types.DrlkUserType
local ProgrammingEventCode = DoorLock.types.ProgramEventCode
local SetCodeStatus        = DoorLock.types.DrlkSetCodeStatus
local ResponseStatus       = DoorLock.types.DrlkPassFailStatus

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("base-lock.yml"),
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

-- Build a ProgrammingEventNotification ZigBee receive message for the given event code and user ID.
local function build_programming_event(event_code, user_id)
  return {
    mock_device.id,
    DoorLock.client.commands.ProgrammingEventNotification.build_test_rx(
      mock_device,
      0x00,                             -- program_event_source (keypad)
      event_code,
      user_id,
      "1234",                           -- PIN (not used by the handler)
      DoorLockUserType.UNRESTRICTED,
      DoorLockUserStatus.OCCUPIED_ENABLED,
      0x0000,                           -- local_alarm_mask
      "data"                            -- user_description
    )
  }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- NOT-BUSY CASES  (manual events from the lock, no command in flight)
-- ─────────────────────────────────────────────────────────────────────────────

test.register_coroutine_test(
  "ProgrammingEventNotification PIN_CODE_ADDED while not busy syncs user and credential entries",
  function()
    -- Route events to the new capabilities handler, not the legacy lockCodes handler.
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_ADDED, 1))
    -- Users table receives the new entry
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } }
        )
      )
    )
    -- Credentials table receives the new entry
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "ProgrammingEventNotification PIN_CODE_DELETED while not busy removes user and credential entries",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
    -- Set up an existing entry by processing a manual addition first.
    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_ADDED, 1))
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()

    -- Now delete the same entry via a manual deletion event.
    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_DELETED, 1))
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials({}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users({}, { visibility = { displayed = false } })
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "ProgrammingEventNotification PIN_CODE_CHANGED while not busy has no effect on table state",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
    -- PIN_CODE_CHANGED is not handled by the notification handler, so no events should
    -- be emitted and table state should remain unchanged.
    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_CHANGED, 1))
    test.wait_for_events()
  end
)

-- ─────────────────────────────────────────────────────────────────────────────
-- BUSY CASES  (notification arrives while one of our commands is in flight)
-- The handler must be a no-op so we do not double-process the result.
-- ─────────────────────────────────────────────────────────────────────────────

test.register_coroutine_test(
  "ProgrammingEventNotification PIN_CODE_ADDED while addCredential is in flight acts as failsafe",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
    -- Simulate an addCredential command being in flight with matching user ID.
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.LOCK_CREDENTIALS.ADD, {})
    mock_device:set_field(constants.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE, {
      userIndex = 1, credentialIndex = 1, credentialType = "pin"
    }, {})

    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_ADDED, 1))
    -- Failsafe path: notification handled as command success, user and credential added, commandResult emitted.
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin" } },
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", userIndex = 1, credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "ProgrammingEventNotification PIN_CODE_CHANGED while updateCredential is in flight acts as failsafe",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
    -- Simulate an updateCredential command being in flight with matching user ID.
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.LOCK_CREDENTIALS.UPDATE, {})
    mock_device:set_field(constants.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE, {
      userIndex = 1, credentialIndex = 1, credentialType = "pin"
    }, {})

    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_CHANGED, 1))
    -- Failsafe path: notification handled as command success, commandResult emitted.
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "updateCredential", statusCode = "success", userIndex = 1, credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "ProgrammingEventNotification PIN_CODE_DELETED while deleteCredential is in flight acts as failsafe",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
    -- First, add a credential so we have something to delete via the failsafe path.
    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_ADDED, 1))
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()

    -- Simulate a deleteCredential command being in flight with matching user ID.
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.LOCK_CREDENTIALS.DELETE, {})
    mock_device:set_field(constants.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE, {
      userIndex = 1, credentialIndex = 1, credentialType = "pin"
    }, {})

    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_DELETED, 1))
    -- Failsafe path: notification handled as command success, credential and user removed, commandResult emitted.
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials({}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users({}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteCredential", statusCode = "success", userIndex = 1, credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()
  end
)

-- ─────────────────────────────────────────────────────────────────────────────
-- BUSY WITH DIFFERENT USER (notification for a different user arrives while
-- a command is in flight; processed as a normal manual event)
-- ─────────────────────────────────────────────────────────────────────────────

test.register_coroutine_test(
  "ProgrammingEventNotification PIN_CODE_ADDED for different user while busy is processed as manual event",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
    -- Simulate an addCredential command in flight for user 1.
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.LOCK_CREDENTIALS.ADD, {})
    mock_device:set_field(constants.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE, {
      userIndex = 1, credentialIndex = 1, credentialType = "pin"
    }, {})

    -- Notification arrives for user 2 (different user) — should be processed as manual event.
    -- The manual handler assigns userIndex = next_index (1, the first available slot), not user_id (2).
    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_ADDED, 2))
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 2, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "ProgrammingEventNotification PIN_CODE_DELETED for different user while busy is processed as manual event",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
    -- First, add a credential for user 2 so we have something to delete.
    -- The manual handler assigns userIndex = next_index (1, the first available slot), not user_id (2).
    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_ADDED, 2))
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 2, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()

    -- Simulate a deleteCredential command in flight for user 1.
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.LOCK_CREDENTIALS.DELETE, {})
    mock_device:set_field(constants.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE, {
      userIndex = 1, credentialIndex = 1, credentialType = "pin"
    }, {})

    -- Notification arrives for user 2 (different user) — should be processed as manual deletion.
    -- Delete handler emits credentials first, then users.
    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_DELETED, 2))
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials({}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users({}, { visibility = { displayed = false } })
      )
    )
    test.wait_for_events()
  end
)

-- ─────────────────────────────────────────────────────────────────────────────
-- POST-BUSY CASES  (busy state was already cleared by the ZigBee response
-- handler before the ProgrammingEventNotification arrives; the notification was
-- sent by the lock in response to our own SetPINCode / ClearPINCode command)
-- ─────────────────────────────────────────────────────────────────────────────

test.register_coroutine_test(
  "Late PIN_CODE_ADDED after addCredential: user and credential already exist; complete no-op",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})

    -- Complete an addCredential flow so both the user and credentials tables already have entries.
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
      DoorLock.client.commands.SetPINCodeResponse.build_test_rx(mock_device, SetCodeStatus.SUCCESS),
    })
    -- User and credential added; commandResult emitted; busy state cleared.
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
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", userIndex = 1, credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()

    -- Late ProgrammingEventNotification PIN_CODE_ADDED for the same slot arrives after busy ends.
    -- The credential is already in the table → find_entry returns it → handler exits early.
    -- Both user and credential already exist, so no events are emitted.
    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_ADDED, 1))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Late PIN_CODE_ADDED when both user and credential already exist: both add_entry calls are no-ops",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})

    -- Populate both tables by processing a not-busy PIN_CODE_ADDED (simulates the completed command state).
    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_ADDED, 1))
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
    test.wait_for_events()

    -- Late notification for the same slot; both add_entry calls return OCCUPIED → no events.
    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_ADDED, 1))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Late PIN_CODE_DELETED after deleteCredential: credential and user already removed; no-op",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})

    -- Populate both tables (user at index 1, credential at index 1).
    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_ADDED, 1))
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
    test.wait_for_events()

    -- Run a standalone deleteCredential flow; this removes the credential but leaves the user.
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
    -- Credential and user entries removed (no remaining credentials for this user). Busy state cleared.
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

    -- Late PIN_CODE_DELETED for the same slot arrives after busy ends.
    -- The credential and user are already gone → therefore nothing happens.
    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_DELETED, 1))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Late PIN_CODE_CHANGED after updateCredential: not handled by notification handler, no events emitted",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})

    -- Seed user and credential so updateCredential has an existing entry to modify.
    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_ADDED, 1))
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
    test.wait_for_events()

    -- Complete an updateCredential flow so the credential entry is updated and busy state is cleared.
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential",
        args = { 1, 1, "pin", "5678" } },
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
        1, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "5678"),
    })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetPINCodeResponse.build_test_rx(mock_device, SetCodeStatus.SUCCESS),
    })
    -- UPDATE doesn't modify the credentials table metadata, only the PIN code (not stored).
    -- The response handler just emits commandResult; busy state is cleared.
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.commandResult(
          { commandName = "updateCredential", statusCode = "success", userIndex = 1, credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()

    -- Late PIN_CODE_CHANGED notification arrives after busy ends.
    -- The notification handler does not handle PIN_CODE_CHANGED → no events emitted.
    test.socket.zigbee:__queue_receive(build_programming_event(ProgrammingEventCode.PIN_CODE_CHANGED, 1))
    test.wait_for_events()
  end
)

test.run_registered_tests()
