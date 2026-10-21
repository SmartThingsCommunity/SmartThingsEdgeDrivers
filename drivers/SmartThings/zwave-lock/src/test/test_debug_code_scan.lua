-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- DEBUG ONLY, do not merge: tests for debug_code_scan.lua

local test         = require "integration_test"
local t_utils      = require "integration_test.utils"
local zw           = require "st.zwave"
local zw_constants = require "st.zwave.constants"
local capabilities = require "st.capabilities"
local json         = require "st.json"
local constants    = require "lock_utils.constants"

--- @type st.zwave.CommandClass.Battery
local Battery      = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.DoorLock
local DoorLock     = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
--- @type st.zwave.CommandClass.UserCode
local UserCode     = (require "st.zwave.CommandClass.UserCode")({ version = 1 })

local YALE_MANUFACTURER_ID = 0x0129

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
  profile               = t_utils.get_profile_definition("base-lock.yml"),
  zwave_endpoints       = zwave_lock_endpoints,
  zwave_manufacturer_id = YALE_MANUFACTURER_ID,
  zwave_product_type    = 0x0002,
  zwave_product_id      = 0x0600,
})

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
end
test.set_test_init_function(test_init)

local function test_init_legacy()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
end

local function refresh_and_expect_scan_start()
  test.socket.capability:__queue_receive({ mock_device.id,
    { capability = "refresh", component = "main", command = "refresh", args = {} }
  })
  test.socket.zwave:__expect_send(DoorLock:OperationGet({}):build_test_tx(mock_device.id))
  test.socket.zwave:__expect_send(Battery:Get({}):build_test_tx(mock_device.id))
  test.socket.zwave:__expect_send(UserCode:UsersNumberGet({}):build_test_tx(mock_device.id))
  test.socket.zwave:__expect_send(UserCode:Get({ user_identifier = 1 }):build_test_tx(mock_device.id))
  test.wait_for_events()
end

test.register_coroutine_test(
  "refresh starts the scan, and an occupied slot is consumed without updating the tables",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    refresh_and_expect_scan_start()

    test.socket.zwave:__queue_receive({ mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_id_status  = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
        user_code       = "1234",
      })
    })
    -- no lockUsers/lockCredentials events are expected; the driver just requests the next slot
    test.socket.zwave:__expect_send(UserCode:Get({ user_identifier = 2 }):build_test_tx(mock_device.id))
    test.wait_for_events()
    assert(mock_device:get_field("debugScanCodeIndex") == 2, "scan should advance to slot 2")
  end
)

test.register_coroutine_test(
  "the scan moves on when a slot does not respond",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    -- the timer for slot 2 must not also fire when time advances past slot 1's timeout
    test.timer.__create_and_queue_test_time_advance_timer(60, "oneshot")
    refresh_and_expect_scan_start()

    test.mock_time.advance_time(5)
    test.socket.zwave:__expect_send(UserCode:Get({ user_identifier = 2 }):build_test_tx(mock_device.id))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "the scan finishes after the last slot",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    refresh_and_expect_scan_start()
    mock_device:set_field("debugScanCodeIndex", 255)

    test.socket.zwave:__queue_receive({ mock_device.id,
      UserCode:Report({
        user_identifier = 255,
        user_id_status  = UserCode.user_id_status.AVAILABLE,
      })
    })
    test.wait_for_events()
    assert(mock_device:get_field("debugScanCodeIndex") == nil, "scan state should be cleared")
  end
)

test.register_coroutine_test(
  "legacy: an occupied slot is consumed without updating lockCodes",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    refresh_and_expect_scan_start()

    test.socket.zwave:__queue_receive({ mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_id_status  = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
        user_code       = "1234",
      })
    })
    -- no lockCodes events are expected; the driver just requests the next slot
    test.socket.zwave:__expect_send(UserCode:Get({ user_identifier = 2 }):build_test_tx(mock_device.id))
    test.wait_for_events()
    assert(mock_device:get_field("debugScanCodeIndex") == 2, "scan should advance to slot 2")
  end,
  { test_init = test_init_legacy }
)

test.register_coroutine_test(
  "legacy: a slot that a code reload is waiting on is also processed by the legacy handler",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.socket.zwave:__queue_receive({ mock_device.id, UserCode:UsersNumberReport({ supported_users = 30 }) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCodes.maxCodes(30, { visibility = { displayed = false } })))
    test.wait_for_events()
    refresh_and_expect_scan_start()
    mock_device:set_field(zw_constants.CHECKING_CODE, 1)

    test.socket.zwave:__queue_receive({ mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_id_status  = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
        user_code       = "1234",
      })
    })
    -- the scan requests the next slot, then the legacy handler records the code and continues its reload
    test.socket.zwave:__expect_send(UserCode:Get({ user_identifier = 2 }):build_test_tx(mock_device.id))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCodes.lockCodes(json.encode({ ["1"] = "Code 1" }), { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCodes.codeChanged("1 set", { data = { codeName = "Code 1" }, state_change = true })))
    test.socket.zwave:__expect_send(UserCode:Get({ user_identifier = 2 }):build_test_tx(mock_device.id))
    test.wait_for_events()
  end,
  { test_init = test_init_legacy }
)

test.run_registered_tests()
