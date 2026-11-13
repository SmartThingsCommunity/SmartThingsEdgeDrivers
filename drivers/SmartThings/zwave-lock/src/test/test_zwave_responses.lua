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
--- @type st.zwave.CommandClass.Battery
local Battery      = (require "st.zwave.CommandClass.Battery")({ version = 1 })
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

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )

    -- driver requests the next code slot.
    test.socket.zwave:__expect_send(
      UserCode:Get({ user_identifier = 2 }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
  end
,
    {
      min_api_version = 15
    })

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

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 20, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()

    assert(mock_device:get_field(constants.SYNC.CODE_INDEX) == nil,
      "CODE_INDEX must be nil after sync completes")
    assert(mock_device:get_field(constants.DRIVER_STATE.BUSY) == false,
      "BUSY must be false after sync completes")
    assert(mock_device:get_field(constants.SYNC.CODES_SYNCED) == constants.SYNC.CODES_SYNC_VERSION,
      "CODES_SYNCED must record the completed sync version")
  end
,
    {
      min_api_version = 15
    })

test.register_coroutine_test(
  "user_code_report: sync does not end early on non-available, non-occupied slots",
  function()
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.SYNC.CODES_FROM_LOCK, {})
    mock_device:set_field(constants.SYNC.CODE_INDEX, 1, {})

    -- more than 5 consecutive "disabled" slots must not count as unoccupied
    for i = 1, 7 do
      test.socket.zwave:__queue_receive({
        mock_device.id,
        UserCode:Report({
          user_identifier = i,
          user_id_status  = UserCode.user_id_status.DISABLED,
        }),
      })
      test.socket.zwave:__expect_send(
        UserCode:Get({ user_identifier = i + 1 }):build_test_tx(mock_device.id)
      )
    end
    test.wait_for_events()

    assert(mock_device:get_field(constants.SYNC.CODE_INDEX) == 8, "sync must still be in progress, index=" .. tostring(mock_device:get_field(constants.SYNC.CODE_INDEX) or "nil"))
    assert(mock_device:get_field(constants.SYNC.CODES_SYNCED) == nil, "sync must not be marked complete")
  end
,
    {
      min_api_version = 15
    })

-- the reads sent by the refresh handler on a device with no cached state
local function expect_refresh_reads()
  test.socket.zwave:__expect_send(DoorLock:OperationGet({}):build_test_tx(mock_device.id))
  test.socket.zwave:__expect_send(Battery:Get({}):build_test_tx(mock_device.id))
  test.socket.zwave:__expect_send(UserCode:UsersNumberGet({}):build_test_tx(mock_device.id))
end

test.register_coroutine_test(
  "sync_device_state: restarts from the first index when the persisted index is from a different sync version",
  function()
    mock_device:set_field(constants.SYNC.CODE_INDEX, 7, { persist = true })
    mock_device:set_field(constants.SYNC.CODE_INDEX_VERSION, constants.SYNC.CODES_SYNC_VERSION - 1, { persist = true })

    -- refresh schedules a delayed sync attempt
    test.timer.__create_and_queue_test_time_advance_timer(15, "oneshot")
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.refresh.ID, command = "refresh", args = {} },
    })
    expect_refresh_reads()
    test.wait_for_events()
    test.mock_time.advance_time(15)
    test.socket.zwave:__expect_send(UserCode:Get({ user_identifier = 1 }):build_test_tx(mock_device.id))
    test.wait_for_events()
    assert(mock_device.persistent_store[constants.SYNC.CODE_INDEX_VERSION] == constants.SYNC.CODES_SYNC_VERSION)

    -- reset shared device state
    mock_device:set_field(constants.DRIVER_STATE.BUSY, false, {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, nil, {})
    mock_device:set_field(constants.SYNC.CODE_INDEX, nil, { persist = true })
    mock_device:set_field(constants.SYNC.CODE_INDEX_VERSION, nil, { persist = true })
  end
,
    {
      min_api_version = 15
    })

test.register_coroutine_test(
  "sync_device_state: does nothing while the device is busy",
  function()
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.LOCK_CREDENTIALS.ADD, {})

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.refresh.ID, command = "refresh", args = {} },
    })
    expect_refresh_reads()
    test.wait_for_events()

    assert(mock_device:get_field(constants.SYNC.CODE_INDEX) == nil, "sync must not start while busy")

    -- reset shared device state
    mock_device:set_field(constants.DRIVER_STATE.BUSY, false, {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, nil, {})
    mock_device:set_field(constants.SYNC.CODE_INDEX, nil, { persist = true })
    mock_device:set_field(constants.SYNC.CODE_INDEX_VERSION, nil, { persist = true })
  end
,
    {
      min_api_version = 15
    })

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

    -- Credential entry added
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } }
        ))
    )
    -- User entry added
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
,
    {
      min_api_version = 15
    })

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
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
,
    {
      min_api_version = 15
    })

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
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 2, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()
  end
,
    {
      min_api_version = 15
    })

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
,
    {
      min_api_version = 15
    })

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
,
    {
      min_api_version = 15
    })

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
,
    {
      min_api_version = 15
    })

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
,
    {
      min_api_version = 15
    })

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
,
    {
      min_api_version = 15
    })

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
,
    {
      min_api_version = 15
    })

-- clear the sync state the tests below leave on the shared mock device
local function reset_sync_state()
  mock_device:set_field(constants.DRIVER_STATE.BUSY, false, {})
  mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, nil, {})
  mock_device:set_field(constants.SYNC.CODE_INDEX, nil, { persist = true })
  mock_device:set_field(constants.SYNC.CODE_INDEX_VERSION, nil, { persist = true })
  mock_device:set_field(constants.SYNC.CONSECUTIVE_UNOCCUPIED_CODES, nil, {})
  mock_device:set_field(constants.SYNC.CODES_SYNCED, nil, { persist = true })
end

test.register_coroutine_test(
  "user_code_report: sync ignores a report for an index that was already processed",
  function()
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.SYNC.CODES_FROM_LOCK, {})
    mock_device:set_field(constants.SYNC.CODE_INDEX, 3, {})

    -- a late, duplicate report for slot 2: no credential is added and no request is sent
    test.socket.zwave:__queue_receive({
      mock_device.id,
      UserCode:Report({
        user_identifier = 2,
        user_id_status  = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
        user_code       = "1234",
      }),
    })
    test.wait_for_events()

    assert(mock_device:get_field(constants.SYNC.CODE_INDEX) == 3, "sync must still be waiting on index 3")
    reset_sync_state()
  end,
  {
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "user_code_report: sync treats a report for an unexpected index as an unoccupied slot and continues",
  function()
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.SYNC.CODES_FROM_LOCK, {})
    mock_device:set_field(constants.SYNC.CODE_INDEX, 3, {})

    -- an occupied report for slot 5 while waiting on slot 3: no credential is recorded at slot 3
    test.socket.zwave:__queue_receive({
      mock_device.id,
      UserCode:Report({
        user_identifier = 5,
        user_id_status  = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
        user_code       = "1234",
      }),
    })
    test.socket.zwave:__expect_send(
      UserCode:Get({ user_identifier = 4 }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()

    assert(mock_device:get_field(constants.SYNC.CONSECUTIVE_UNOCCUPIED_CODES) == 1,
      "an unexpected report counts as an unoccupied code")
    reset_sync_state()
  end,
  {
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "user_code_report: persists the sync code index while sync is in progress",
  function()
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.SYNC.CODES_FROM_LOCK, {})
    mock_device:set_field(constants.SYNC.CODE_INDEX, 1, {})

    -- unoccupied slot: no credential events, just advance to the next index
    test.socket.zwave:__queue_receive({
      mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_id_status  = UserCode.user_id_status.AVAILABLE,
      }),
    })
    test.socket.zwave:__expect_send(
      UserCode:Get({ user_identifier = 2 }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()

    -- the index must be in the persistent store so sync can resume after a driver restart
    assert(mock_device.persistent_store[constants.SYNC.CODE_INDEX] == 2)
    assert(mock_device.transient_store[constants.SYNC.CODE_INDEX] == nil)
    reset_sync_state()
  end,
  {
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "user_code_report: clears the consecutive unoccupied counter when the sync completes",
  function()
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.SYNC.CODES_FROM_LOCK, {})
    mock_device:set_field(constants.SYNC.CODE_INDEX, 6, { persist = true })
    mock_device:set_field(constants.SYNC.CONSECUTIVE_UNOCCUPIED_CODES, 5, {})

    test.socket.zwave:__queue_receive({
      mock_device.id,
      UserCode:Report({
        user_identifier = 6,
        user_id_status  = UserCode.user_id_status.AVAILABLE,
      }),
    })
    test.wait_for_events()

    assert(mock_device:get_field(constants.SYNC.CONSECUTIVE_UNOCCUPIED_CODES) == nil)
    assert(mock_device:get_field(constants.SYNC.CODES_SYNCED) == constants.SYNC.CODES_SYNC_VERSION)
    reset_sync_state()
  end,
  {
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "sync_device_state: retries a stalled sync once the busy window has expired",
  function()
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time() - 60, {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.SYNC.CODES_FROM_LOCK, {})
    mock_device:set_field(constants.SYNC.CODE_INDEX, 4, { persist = true })
    mock_device:set_field(constants.SYNC.CODE_INDEX_VERSION, constants.SYNC.CODES_SYNC_VERSION, { persist = true })

    -- refresh schedules a delayed sync attempt, which resumes from the persisted index
    test.timer.__create_and_queue_test_time_advance_timer(15, "oneshot")
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.refresh.ID, command = "refresh", args = {} },
    })
    expect_refresh_reads()
    test.wait_for_events()
    test.mock_time.advance_time(15)
    test.socket.zwave:__expect_send(
      UserCode:Get({ user_identifier = 4 }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
    reset_sync_state()
  end,
  {
    min_api_version = 15
  }
)

test.run_registered_tests()
