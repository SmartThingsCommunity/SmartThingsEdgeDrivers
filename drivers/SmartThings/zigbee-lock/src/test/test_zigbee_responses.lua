-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Additional tests for lock_handlers/zigbee_responses.lua to improve coverage.
-- Covers:
--   • get_pin_code_response: sync codes from lock flow
--   • programming_event_notification: Yale/ASSA ABLOY user_id >= 256 shift
--   • operating_event_notification: keypad source with lockUsers capability
--   • operating_event_notification: schedule events with non-keypad source (auto method)
--   • alarm: alarm codes 0 and 1
--   • lock_state: attribute handler with delay logic
--   • max_pin_code_length / min_pin_code_length: attribute handlers
--   • number_of_pin_users_supported: attribute handler with profile migration

local test              = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils           = require "integration_test.utils"
local capabilities      = require "st.capabilities"
local clusters          = require "st.zigbee.zcl.clusters"
local DoorLock          = clusters.DoorLock
local Alarms            = clusters.Alarms
local constants         = require "lock_utils.constants"
local table_utils       = require "lock_utils.tables"

local DoorLockUserStatus   = DoorLock.types.DrlkUserStatus
local DoorLockUserType     = DoorLock.types.DrlkUserType
local OperationEventCode   = DoorLock.types.OperationEventCode
local OperationEventSource = DoorLock.types.DrlkOperationEventSource
local ProgrammingEventCode = DoorLock.types.ProgramEventCode
local LockState            = DoorLock.attributes.LockState

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("base-lock.yml"),
})

local mock_device_yale = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("base-lock.yml"),
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "Yale",
      model = "YRD256",
      server_clusters = { DoorLock.ID },
    },
  },
})

local mock_device_no_lock_codes = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("lock-without-codes.yml"),
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_device_yale)
  test.mock_device.add_test_device(mock_device_no_lock_codes)
end

test.set_test_init_function(test_init)

-- Helper: build OperatingEventNotification
local function build_operating_event(device, event_code, event_source, user_id)
  return {
    device.id,
    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
      device,
      event_source,
      event_code,
      user_id or 0,
      "1234",
      0x0000,
      "data"
    ),
  }
end

-- Helper: build ProgrammingEventNotification
local function build_programming_event(device, event_code, user_id)
  return {
    device.id,
    DoorLock.client.commands.ProgrammingEventNotification.build_test_rx(
      device,
      0x00,
      event_code,
      user_id,
      "1234",
      DoorLockUserType.UNRESTRICTED,
      DoorLockUserStatus.OCCUPIED_ENABLED,
      0x0000,
      "data"
    ),
  }
end

-- ============================================================================
-- get_pin_code_response: sync codes from lock
-- ============================================================================

test.register_coroutine_test(
  "get_pin_code_response: syncs codes from lock and requests next code",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
    -- Set up the sync state
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.SYNC.CODES_FROM_LOCK, {})
    mock_device:set_field(constants.SYNC.CODE_INDEX, 1, {})

    -- Receive GetPINCodeResponse for user_id 1
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
        mock_device,
        1,                                    -- user_id
        DoorLockUserStatus.OCCUPIED_ENABLED,
        DoorLockUserType.UNRESTRICTED,
        "1234"                                -- PIN code
      ),
    })

    -- Should add user entry
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "User 1", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    -- Should add credential entry
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "User 1" } },
          { visibility = { displayed = false } }
        ))
    )
    -- Should request next code
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.GetPINCode(mock_device, 2),
    })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "get_pin_code_response: completes sync when max entries reached",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})

    -- Set up the sync state at the last code index
    -- get_max_entries defaults to 20 when attribute is missing, so use user_id 20
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.SYNC.CODES_FROM_LOCK, {})
    mock_device:set_field(constants.SYNC.CODE_INDEX, 20, {})

    -- Receive GetPINCodeResponse for user_id 20 (at default max)
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
        mock_device,
        20,
        DoorLockUserStatus.OCCUPIED_ENABLED,
        DoorLockUserType.UNRESTRICTED,
        "1234"
      ),
    })

    -- Should add entries
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 20, userName = "User 20", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 20, credentialIndex = 20, credentialType = "pin", credentialName = "User 20" } },
          { visibility = { displayed = false } }
        ))
    )
    -- Should NOT request next code (sync complete)
    test.wait_for_events()

    -- Verify sync state is cleared (clear_busy_state sets BUSY to false, not nil)
    assert(mock_device:get_field(constants.SYNC.CODE_INDEX) == nil)
    assert(mock_device:get_field(constants.DRIVER_STATE.BUSY) == false)
  end
)

-- ============================================================================
-- programming_event_notification: Yale user_id shift
-- ============================================================================

test.register_coroutine_test(
  "programming_event_notification: Yale device shifts user_id >= 256",
  function()
    mock_device_yale:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})

    -- Send a PIN_CODE_ADDED with user_id 256 (0x100), which should shift to 1
    test.socket.zigbee:__queue_receive(
      build_programming_event(mock_device_yale, ProgrammingEventCode.PIN_CODE_ADDED, 256)
    )

    -- After shifting 256 >> 8 = 1, should add entries for user_id 1
    test.socket.capability:__expect_send(
      mock_device_yale:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "User 1", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device_yale:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "User 1" } },
          { visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- operating_event_notification: keypad with lockUsers (user info lookup)
-- ============================================================================

test.register_coroutine_test(
  "operating_event_notification: keypad unlock includes user info when user and credential exist",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})

    -- First, add a user entry (using valid userType "guest")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "John Doe", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    table_utils.add_entry(mock_device, "users", {
      userIndex = 1,
      userName = "John Doe",
      userType = "guest",
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "John's PIN" } },
          { visibility = { displayed = false } }
        ))
    )
    table_utils.add_entry(mock_device, "credentials", {
      userIndex = 1,
      credentialIndex = 1,
      credentialType = "pin",
      credentialName = "John's PIN",
    })
    test.wait_for_events()

    -- Send unlock event from keypad with user_id 1
    test.socket.zigbee:__queue_receive(
      build_operating_event(mock_device, OperationEventCode.UNLOCK, OperationEventSource.KEYPAD, 1)
    )

    -- Should emit unlocked with user info
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lock.lock.unlocked({
          data = {
            method = "keypad",
            userIndex = 1,
            userName = "John Doe",
            userType = "guest",
          },
        })
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "operating_event_notification: keypad unlock with unknown user uses default name",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})

    -- Send unlock event from keypad with user_id 99 (no matching entry)
    test.socket.zigbee:__queue_receive(
      build_operating_event(mock_device, OperationEventCode.UNLOCK, OperationEventSource.KEYPAD, 99)
    )

    -- Should emit unlocked with default user name
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lock.lock.unlocked({
          data = {
            method = "keypad",
            userIndex = 99,
            userName = "User 99",
          },
        })
      )
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- operating_event_notification: schedule events with "auto" method
-- ============================================================================

test.register_coroutine_test(
  "operating_event_notification: SCHEDULE_LOCK with RF source uses auto method",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})

    test.socket.zigbee:__queue_receive(
      build_operating_event(mock_device, OperationEventCode.SCHEDULE_LOCK, OperationEventSource.RF, 0)
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lock.lock.locked({ data = { method = "auto" } })
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "operating_event_notification: SCHEDULE_UNLOCK with MANUAL source uses auto method",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})

    test.socket.zigbee:__queue_receive(
      build_operating_event(mock_device, OperationEventCode.SCHEDULE_UNLOCK, OperationEventSource.MANUAL, 0)
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lock.lock.unlocked({ data = { method = "auto" } })
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "operating_event_notification: AUTO_LOCK with RF source uses auto method",
  function()
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})

    test.socket.zigbee:__queue_receive(
      build_operating_event(mock_device, OperationEventCode.AUTO_LOCK, OperationEventSource.RF, 0)
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lock.lock.locked({ data = { method = "auto" } })
      )
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- alarm: alarm handler
-- ============================================================================

test.register_coroutine_test(
  "alarm: alarm code 0 emits lock.unknown",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      Alarms.client.commands.Alarm.build_test_rx(mock_device, 0, DoorLock.ID),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.lock.unknown())
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "alarm: alarm code 1 emits lock.unknown",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      Alarms.client.commands.Alarm.build_test_rx(mock_device, 1, DoorLock.ID),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.lock.unknown())
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "alarm: unrecognized alarm code does not emit event",
  function()
    -- Alarm code 16 (low battery) is not in ALARM_REPORT map
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      Alarms.client.commands.Alarm.build_test_rx(mock_device, 16, DoorLock.ID),
    })

    -- No event should be emitted
    test.wait_for_events()
  end
)

-- ============================================================================
-- lock_state: attribute handler
-- ============================================================================

test.register_coroutine_test(
  "lock_state: LOCKED state emits locked event",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      LockState:build_test_attr_report(mock_device, LockState.LOCKED),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.lock.locked())
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "lock_state: UNLOCKED state emits unlocked event",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      LockState:build_test_attr_report(mock_device, LockState.UNLOCKED),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.lock.unlocked())
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "lock_state: NOT_FULLY_LOCKED state emits unknown event",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      LockState:build_test_attr_report(mock_device, LockState.NOT_FULLY_LOCKED),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.lock.unknown())
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- max_pin_code_length / min_pin_code_length: attribute handlers
-- ============================================================================

test.register_coroutine_test(
  "max_pin_code_length: emits maxPinCodeLen event",
  function()
    -- Set SLGA_MIGRATED so we route to the new handlers
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.attributes.MaxPINCodeLength:build_test_attr_report(mock_device, 8),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.maxPinCodeLen(8, { visibility = { displayed = false } })
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "min_pin_code_length: emits minPinCodeLen event",
  function()
    -- Set SLGA_MIGRATED so we route to the new handlers
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.attributes.MinPINCodeLength:build_test_attr_report(mock_device, 4),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.minPinCodeLen(4, { visibility = { displayed = false } })
      )
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- number_of_pin_users_supported: attribute handler
-- ============================================================================

test.register_coroutine_test(
  "number_of_pin_users_supported: emits pinUsersSupported and totalUsersSupported",
  function()
    -- Set SLGA_MIGRATED so we route to the new handlers
    mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      DoorLock.attributes.NumberOfPINUsersSupported:build_test_attr_report(mock_device, 20),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.pinUsersSupported(20, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.totalUsersSupported(20, { visibility = { displayed = false } })
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "number_of_pin_users_supported: triggers profile migration when device has no lockCodes",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device_no_lock_codes.id,
      DoorLock.attributes.NumberOfPINUsersSupported:build_test_attr_report(mock_device_no_lock_codes, 10),
    })

    -- Should trigger profile update to base-lock
    mock_device_no_lock_codes:expect_metadata_update({ profile = "base-lock" })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "number_of_pin_users_supported: zero value does not trigger profile migration",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device_no_lock_codes.id,
      DoorLock.attributes.NumberOfPINUsersSupported:build_test_attr_report(mock_device_no_lock_codes, 0),
    })

    -- No profile update should occur (value is 0)
    test.wait_for_events()
  end
)

test.run_registered_tests()
