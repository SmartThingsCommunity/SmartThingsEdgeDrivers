-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Integration tests for the lifecycle handlers defined in init.lua:
--   added (device_added), infoChanged (info_changed), init (LockLifecycle.init)
--
-- Removed: doConfigure tests — z-wave drivers have no doConfigure lifecycle event.
-- Removed: init SLGA_MIGRATED without lockCodes test — z-wave init sends no protocol
--          messages; there is no NumberOfPINUsersSupported read on init.

local test       = require "integration_test"
local t_utils    = require "integration_test.utils"
local capabilities = require "st.capabilities"
local zw         = require "st.zwave"
local constants  = require "lock_utils.constants"

--- @type st.zwave.CommandClass.DoorLock
local DoorLock   = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
--- @type st.zwave.CommandClass.Battery
local Battery    = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.UserCode
local UserCode   = (require "st.zwave.CommandClass.UserCode")({ version = 1 })

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

-- base-lock profile: lock + lockCodes + lockCredentials + lockUsers + battery
local mock_device_base = test.mock_device.build_test_zwave_device({
  profile         = t_utils.get_profile_definition("base-lock.yml"),
  zwave_endpoints = zwave_lock_endpoints,
})

-- Same profile but provisioning_state = "TYPED" (freshly fingerprinted)
local mock_device_typed = test.mock_device.build_test_zwave_device({
  profile             = t_utils.get_profile_definition("base-lock.yml"),
  zwave_endpoints     = zwave_lock_endpoints,
  _provisioning_state = "TYPED",
})

-- lock-battery profile: lock + battery only (no lockCodes / lockCredentials)
local mock_device_battery = test.mock_device.build_test_zwave_device({
  profile         = t_utils.get_profile_definition("lock-battery.yml"),
  zwave_endpoints = zwave_lock_endpoints,
})

local function make_test_init(device)
  return function()
    test.disable_startup_messages()
    test.mock_device.add_test_device(device)
  end
end

-- ============================================================================
-- added (device_added)
-- ============================================================================

test.register_coroutine_test(
  "added: TYPED device with lockCodes emits migrated event, persists SLGA_MIGRATED, and injects refresh",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_typed.id, "added" })

    -- Migrated event emitted for TYPED+lockCodes device
    test.socket.capability:__expect_send(
      mock_device_typed:generate_test_message("main",
        capabilities.lockCodes.migrated(true, { visibility = { displayed = false } }))
    )
    -- inject_capability_command calls the refresh handler:
    -- DoorLock:OperationGet, Battery:Get, UserCode:UsersNumberGet (no cached values)
    test.socket.zwave:__expect_send(DoorLock:OperationGet({}):build_test_tx(mock_device_typed.id))
    test.socket.zwave:__expect_send(Battery:Get({}):build_test_tx(mock_device_typed.id))
    test.socket.zwave:__expect_send(UserCode:UsersNumberGet({}):build_test_tx(mock_device_typed.id))
    test.wait_for_events()

    assert(
      mock_device_typed:get_field(constants.DRIVER_STATE.SLGA_MIGRATED) == true,
      "SLGA_MIGRATED must be true after added fires for a TYPED device"
    )
  end,
  { test_init = make_test_init(mock_device_typed) }
)

test.register_coroutine_test(
  "added: non-TYPED (PROVISIONED) device with lockCodes does NOT emit migrated but still injects refresh",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_base.id, "added" })

    -- No migrated capability event expected
    test.socket.zwave:__expect_send(DoorLock:OperationGet({}):build_test_tx(mock_device_base.id))
    test.socket.zwave:__expect_send(Battery:Get({}):build_test_tx(mock_device_base.id))
    test.socket.zwave:__expect_send(UserCode:UsersNumberGet({}):build_test_tx(mock_device_base.id))
    test.wait_for_events()

    assert(
      mock_device_base:get_field(constants.DRIVER_STATE.SLGA_MIGRATED) ~= true,
      "SLGA_MIGRATED must NOT be set for a non-TYPED device"
    )
  end,
  { test_init = make_test_init(mock_device_base) }
)

test.register_coroutine_test(
  "added: device without lockCodes does NOT emit migrated event but still injects refresh",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_battery.id, "added" })

    -- No migrated event; lock-battery has no lockCredentials so no UsersNumberGet
    test.socket.zwave:__expect_send(DoorLock:OperationGet({}):build_test_tx(mock_device_battery.id))
    test.socket.zwave:__expect_send(Battery:Get({}):build_test_tx(mock_device_battery.id))
    test.wait_for_events()
  end,
  { test_init = make_test_init(mock_device_battery) }
)

-- ============================================================================
-- init (LockLifecycle.init)
-- ============================================================================

test.register_coroutine_test(
  "init: device with lockCodes and SLGA_MIGRATED=true emits migrated + supportedCredentials",
  function()
    mock_device_base:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })

    test.socket.device_lifecycle:__queue_receive({ mock_device_base.id, "init" })
    test.socket.capability:__expect_send(
      mock_device_base:generate_test_message("main",
        capabilities.lockCodes.migrated(true, { visibility = { displayed = false } }))
    )
    test.socket.capability:__expect_send(
      mock_device_base:generate_test_message("main",
        capabilities.lockCredentials.supportedCredentials({ "pin" }, { visibility = { displayed = false } }))
    )
    test.wait_for_events()
  end,
  { test_init = make_test_init(mock_device_base) }
)

test.register_coroutine_test(
  "init: device with lockCodes but SLGA_MIGRATED not set does nothing",
  function()
    -- SLGA_MIGRATED is not set; no events or z-wave sends expected
    test.socket.device_lifecycle:__queue_receive({ mock_device_base.id, "init" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(mock_device_base) }
)

test.register_coroutine_test(
  "init: lock-battery device (no lockCodes) does nothing regardless of SLGA_MIGRATED",
  function()
    mock_device_battery:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })
    -- lock-battery has no lockCodes → if branch is false → no events, no z-wave sends
    test.socket.device_lifecycle:__queue_receive({ mock_device_battery.id, "init" })
    test.wait_for_events()
  end,
  { test_init = make_test_init(mock_device_battery) }
)

-- ============================================================================
test.run_registered_tests()
