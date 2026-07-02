-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Tests for lock_handlers/zwave_responses.lua
-- Covers:
--   • user_code_report: sync-codes-from-lock flow (advances slot, completes sync)
--   • user_code_report: out-of-band ENABLED code creates user+credential entries
--   • user_code_event_handler (via Notification:Report): NEW_USER_CODE_ADDED out-of-band
--   • user_code_event_handler: multi-byte event_parameter (byte 3 carries user_id)
--   • door_operation_event_handler: KEYPAD_UNLOCK with user info lookup
--   • door_operation_event_handler: KEYPAD_UNLOCK with unknown credential
--   • door_operation_event_handler: AUTO_LOCK_LOCKED_OPERATION → locked/auto
--   • DoorLock:OperationReport DOOR_SECURED / DOOR_UNSECURED → locked / unlocked
--   • UserCode:UsersNumberReport → pinUsersSupported + totalUsersSupported
--
-- Removed: alarm tests — z-wave alarm decoding is only in the legacy-handlers sub-driver
--          for non-SLGA devices; not applicable to the main SLGA driver path.
-- Removed: max/min PIN code length tests — no z-wave equivalent attribute.
-- Removed: NOT_FULLY_LOCKED lock_state test — no clean z-wave OperationReport equivalent.
-- Removed: NumberOfPINUsersSupported profile-migration tests — that logic lives in the
--          zigbee legacy sub-driver; users_number_report in z-wave only emits events.

local test         = require "integration_test"
local t_utils      = require "integration_test.utils"
local capabilities = require "st.capabilities"
local zw           = require "st.zwave"
local constants    = require "lock_utils.constants"

--- @type st.zwave.CommandClass.DoorLock
local DoorLock     = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
--- @type st.zwave.CommandClass.UserCode
local UserCode     = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })

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
  profile         = t_utils.get_profile_definition("base-lock.yml"),
  zwave_endpoints = zwave_lock_endpoints,
})

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
end
test.set_test_init_function(test_init)

-- ============================================================================
-- user_code_report: sync codes from lock
-- During sync (CODES_FROM_LOCK busy state), ENABLED slots advance the index
-- without adding table entries; only AVAILABLE slots remove local entries.
-- ============================================================================

test.register_coroutine_test(
  "user_code_report: sync advances to next code slot when slot is occupied",
  function()
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.SYNC.CODES_FROM_LOCK, {})
    mock_device:set_field(constants.SYNC.CODE_INDEX, 1, {})

    -- Receive UserCode:Report for slot 1 (occupied)
    test.socket.zwave:__queue_receive({
      mock_device.id,
      UserCode:Report({
        user_identifier  = 1,
        user_id_status   = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
        user_code        = "1234",
      }),
    })

    -- No table entries added during sync for ENABLED slots;
    -- driver requests the next code slot.
    test.socket.zwave:__expect_send(
      UserCode:Get({ user_identifier = 2 }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "user_code_report: sync completes when the last slot is reached",
  function()
    -- get_max_entries defaults to 20 when the attribute is missing
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.SYNC.CODES_FROM_LOCK, {})
    mock_device:set_field(constants.SYNC.CODE_INDEX, 20, {})

    test.socket.zwave:__queue_receive({
      mock_device.id,
      UserCode:Report({
        user_identifier = 20,
        user_id_status  = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
        user_code       = "1234",
      }),
    })

    -- No next-slot request; sync is complete
    test.wait_for_events()

    assert(mock_device:get_field(constants.SYNC.CODE_INDEX) == nil,
      "CODE_INDEX must be nil after sync completes")
    assert(mock_device:get_field(constants.DRIVER_STATE.BUSY) == false,
      "BUSY must be false after sync completes")
  end
)

test.register_coroutine_test(
  "user_code_report: out-of-band ENABLED code creates user and credential entries",
  function()
    -- command_in_progress == nil → out-of-band path
    test.socket.zwave:__queue_receive({
      mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_id_status  = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
        user_code       = "1234",
      }),
    })

    -- User entry added
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    -- Credential entry added
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- user_code_event_handler (ACCESS_CONTROL Notification:Report)
-- ============================================================================

test.register_coroutine_test(
  "user_code_event: NEW_USER_CODE_ADDED out-of-band creates user and credential entries",
  function()
    -- event_parameter = single byte encodes user_id = 1
    test.socket.zwave:__queue_receive({
      mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event             = Notification.event.access_control.NEW_USER_CODE_ADDED,
        event_parameter   = string.char(1),
      }),
    })

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
  end
)

test.register_coroutine_test(
  "user_code_event: multi-byte event_parameter uses byte 3 to extract user_id",
  function()
    -- 3-byte event_parameter: bytes are (0, 0, 2) → byte 3 = 2 → user_id = 2
    test.socket.zwave:__queue_receive({
      mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event             = Notification.event.access_control.NEW_USER_CODE_ADDED,
        event_parameter   = string.char(0, 0, 2),
      }),
    })

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
          { { userIndex = 1, credentialIndex = 2, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- door_operation_event_handler (ACCESS_CONTROL Notification:Report)
-- ============================================================================

test.register_coroutine_test(
  "door_operation_event: KEYPAD_UNLOCK_OPERATION includes user info when credential exists",
  function()
    -- Seed persisted user/credential tables so the driver's lookup succeeds.
    mock_device:set_field("persistedUsers", {
      { userIndex = 1, userName = "John Doe", userType = "guest" },
    }, { persist = true })
    mock_device:set_field("persistedCredentials", {
      { userIndex = 1, credentialIndex = 1, credentialType = "pin" },
    }, { persist = true })

    test.socket.zwave:__queue_receive({
      mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event             = Notification.event.access_control.KEYPAD_UNLOCK_OPERATION,
        event_parameter   = string.char(1),
      }),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lock.lock.unlocked({
          data = {
            method    = "keypad",
            userIndex = 1,
            userName  = "John Doe",
            userType  = "guest",
          },
        })
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "door_operation_event: KEYPAD_UNLOCK_OPERATION with unknown credential sets userIndex from event_parameter",
  function()
    -- No credential seeded for slot 99
    test.socket.zwave:__queue_receive({
      mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event             = Notification.event.access_control.KEYPAD_UNLOCK_OPERATION,
        event_parameter   = string.char(99),
      }),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lock.lock.unlocked({
          data = {
            method    = "keypad",
            userIndex = 99,
          },
        })
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "door_operation_event: AUTO_LOCK_LOCKED_OPERATION emits locked with auto method",
  function()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event             = Notification.event.access_control.AUTO_LOCK_LOCKED_OPERATION,
        event_parameter   = "",
      }),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lock.lock.locked({ data = { method = "auto" } })
      )
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- DoorLock:OperationReport → lock state
-- Removed: NOT_FULLY_LOCKED — no clean z-wave OperationReport equivalent.
-- ============================================================================

test.register_coroutine_test(
  "OperationReport: DOOR_SECURED emits locked event",
  function()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      DoorLock:OperationReport({ door_lock_mode = DoorLock.door_lock_mode.DOOR_SECURED }),
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.lock.locked())
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "OperationReport: DOOR_UNSECURED emits unlocked event",
  function()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      DoorLock:OperationReport({ door_lock_mode = DoorLock.door_lock_mode.DOOR_UNSECURED }),
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.lock.unlocked())
    )
    test.wait_for_events()
  end
)

-- ============================================================================
-- users_number_report: UserCode:UsersNumberReport
-- ============================================================================

test.register_coroutine_test(
  "users_number_report: emits pinUsersSupported and totalUsersSupported",
  function()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      UserCode:UsersNumberReport({ supported_users = 20 }),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.totalUsersSupported(
          20, { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.pinUsersSupported(
          20, { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
)

test.run_registered_tests()
