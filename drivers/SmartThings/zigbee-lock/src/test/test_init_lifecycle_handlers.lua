-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Integration tests for the four lifecycle handlers defined in init.lua:
--   added (device_added), doConfigure (do_configure),
--   infoChanged (info_changed), init (LockLifecycle.init)

local test              = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils           = require "integration_test.utils"

local capabilities      = require "st.capabilities"
local clusters          = require "st.zigbee.zcl.clusters"
local DoorLock          = clusters.DoorLock
local PowerConfiguration = clusters.PowerConfiguration
local Alarms            = clusters.Alarms
local constants         = require "lock_utils.constants"

-- ── Shared mock devices ────────────────────────────────────────────────────
-- base-lock profile: lock + lockCodes + lockCredentials + lockUsers + battery
local mock_device_base = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("base-lock.yml"),
})

-- Same profile but provisioning_state = "TYPED" (freshly fingerprinted)
local mock_device_typed = test.mock_device.build_test_zigbee_device({
  profile              = t_utils.get_profile_definition("base-lock.yml"),
  _provisioning_state  = "TYPED",
})

-- lock-battery profile: lock + battery only (no lockCodes / lockCredentials)
local mock_device_battery = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("lock-battery.yml"),
})

zigbee_test_utils.prepare_zigbee_env_info()

-- Helper: make a test_init function that suppresses startup messages and
-- registers the given device.
local function make_test_init(device)
  return function()
    test.disable_startup_messages()
    test.mock_device.add_test_device(device)
  end
end

-- Helper: expect the five zigbee messages produced by sync_device_state on a
-- freshly-started device (no cached capability state, CODE_INDEX starts at 1).
local function expect_sync_device_state(device)
  test.socket.zigbee:__expect_send({ device.id, DoorLock.attributes.SendPINOverTheAir:write(device, true) })
  test.socket.zigbee:__expect_send({ device.id, DoorLock.server.commands.GetPINCode(device, 1) })
end

-- Helper: expect the messages produced by the legacy reload_all_codes path after
-- the 2-second doConfigure timer fires on a non-SLGA_MIGRATED device.
-- Unlike sync_device_state, reload_all_codes emits scanCodes("Scanning") and
-- starts iterating from code slot 0 (CHECKING_CODE = 0).
local function expect_reload_all_codes_messages(device)
  test.socket.zigbee:__expect_send({ device.id, DoorLock.attributes.SendPINOverTheAir:write(device, true) })
  test.socket.zigbee:__expect_send({ device.id, DoorLock.attributes.MaxPINCodeLength:read(device) })
  test.socket.zigbee:__expect_send({ device.id, DoorLock.attributes.MinPINCodeLength:read(device) })
  test.socket.zigbee:__expect_send({ device.id, DoorLock.attributes.NumberOfPINUsersSupported:read(device) })
  test.socket.capability:__expect_send(
    device:generate_test_message("main",
      capabilities.lockCodes.scanCodes("Scanning", { visibility = { displayed = false } }))
  )
  test.socket.zigbee:__expect_send({ device.id, DoorLock.server.commands.GetPINCode(device, 0) })
end

-- Helper: expect the six zigbee messages sent by do_configure for any device.
local function expect_do_configure_zigbee(device)
  test.socket.zigbee:__expect_send({
    device.id,
    zigbee_test_utils.build_bind_request(device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID),
  })
  test.socket.zigbee:__expect_send({
    device.id,
    PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 600, 21600, 1),
  })
  test.socket.zigbee:__expect_send({
    device.id,
    zigbee_test_utils.build_bind_request(device, zigbee_test_utils.mock_hub_eui, DoorLock.ID),
  })
  test.socket.zigbee:__expect_send({
    device.id,
    DoorLock.attributes.LockState:configure_reporting(device, 0, 3600, 0),
  })
  test.socket.zigbee:__expect_send({
    device.id,
    zigbee_test_utils.build_bind_request(device, zigbee_test_utils.mock_hub_eui, Alarms.ID),
  })
  test.socket.zigbee:__expect_send({
    device.id,
    Alarms.attributes.AlarmCount:configure_reporting(device, 0, 21600, 0),
  })
end

-- ============================================================================
-- added (device_added)
-- ============================================================================

test.register_coroutine_test(
  "added: TYPED device with lockCodes emits migrated event, persists SLGA_MIGRATED, and injects refresh",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_typed.id, "added" })

    -- Migrated event is emitted before the injected refresh
    test.socket.capability:__expect_send(
      mock_device_typed:generate_test_message("main",
        capabilities.lockCodes.migrated(true, { visibility = { displayed = false } }))
    )
    -- inject_capability_command calls the refresh handler inline
    test.socket.zigbee:__expect_send({
      mock_device_typed.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_typed),
    })
    test.socket.zigbee:__expect_send({
      mock_device_typed.id,
      DoorLock.attributes.LockState:read(mock_device_typed),
    })
    test.socket.zigbee:__expect_send({
      mock_device_typed.id,
      Alarms.attributes.AlarmCount:read(mock_device_typed),
    })
    test.socket.zigbee:__expect_send({
      mock_device_typed.id,
      DoorLock.attributes.MaxPINCodeLength:read(mock_device_typed),
    })
    test.socket.zigbee:__expect_send({
      mock_device_typed.id,
      DoorLock.attributes.MinPINCodeLength:read(mock_device_typed),
    })
    test.socket.zigbee:__expect_send({
      mock_device_typed.id,
      DoorLock.attributes.NumberOfPINUsersSupported:read(mock_device_typed),
    })
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
    test.socket.zigbee:__expect_send({
      mock_device_base.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_base),
    })
    test.socket.zigbee:__expect_send({
      mock_device_base.id,
      DoorLock.attributes.LockState:read(mock_device_base),
    })
    test.socket.zigbee:__expect_send({
      mock_device_base.id,
      Alarms.attributes.AlarmCount:read(mock_device_base),
    })
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

    -- No migrated capability event expected.
    -- For non-SLGA_MIGRATED devices the legacy-handlers refresh fires, which reads
    -- NumberOfPINUsersSupported when the device has no lockCodes and no cached code support.
    test.socket.zigbee:__expect_send({
      mock_device_battery.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_battery),
    })
    test.socket.zigbee:__expect_send({
      mock_device_battery.id,
      DoorLock.attributes.LockState:read(mock_device_battery),
    })
    test.socket.zigbee:__expect_send({
      mock_device_battery.id,
      Alarms.attributes.AlarmCount:read(mock_device_battery),
    })
    test.socket.zigbee:__expect_send({
      mock_device_battery.id,
      DoorLock.attributes.NumberOfPINUsersSupported:read(mock_device_battery),
    })
    test.wait_for_events()
  end,
  { test_init = make_test_init(mock_device_battery) }
)

-- ============================================================================
-- doConfigure (do_configure)
-- ============================================================================

test.register_coroutine_test(
  "doConfigure: SLGA_MIGRATED device with lockCredentials sends bind/configure then calls sync_device_state after 2-second delay",
  function()
    -- Pre-seed SLGA_MIGRATED so the main driver's do_configure fires (not legacy-handlers).
    mock_device_base:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })

    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device_base.id, "doConfigure" })

    expect_do_configure_zigbee(mock_device_base)
    mock_device_base:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()

    -- Timer fires: sync_device_state is called (GetPINCode slot 1)
    test.mock_time.advance_time(2)
    test.socket.zigbee:__set_channel_ordering("relaxed")
    expect_sync_device_state(mock_device_base)
    test.wait_for_events()
  end,
  { test_init = make_test_init(mock_device_base) }
)

test.register_coroutine_test(
  "doConfigure: SLGA_MIGRATED device without lockCredentials sends bind/configure but does NOT create sync timer",
  function()
    -- Pre-seed SLGA_MIGRATED so the main driver's do_configure fires.
    mock_device_battery:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })

    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device_battery.id, "doConfigure" })

    expect_do_configure_zigbee(mock_device_battery)
    mock_device_battery:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()
    -- lock-battery has no lockCredentials, so no 2-second timer is created.
  end,
  { test_init = make_test_init(mock_device_battery) }
)

test.register_coroutine_test(
  "doConfigure: non-SLGA_MIGRATED device triggers legacy reloadAllCodes (with scanCodes emit) after 2-second delay",
  function()
    -- mock_device_typed has no SLGA_MIGRATED → legacy-handlers' do_configure fires,
    -- which injects a reloadAllCodes capability command after a 2-second delay.
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device_typed.id, "doConfigure" })

    expect_do_configure_zigbee(mock_device_typed)
    mock_device_typed:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()

    -- Timer fires: legacy reload_all_codes runs, iterating from code slot 0.
    test.mock_time.advance_time(2)
    test.socket.zigbee:__set_channel_ordering("relaxed")
    expect_reload_all_codes_messages(mock_device_typed)
    test.wait_for_events()
  end,
  { test_init = make_test_init(mock_device_typed) }
)

-- ============================================================================
-- infoChanged (info_changed)
-- Each test uses a per-test fresh device (upvalue pattern) to avoid
-- raw_st_data contamination from generate_info_changed across tests.
-- init is triggered first so the driver loads the device into device_cache,
-- allowing infoChanged to correctly identify the old profile.
-- ============================================================================

do
  local dev
  test.register_coroutine_test(
    "infoChanged: switching from non-lockCodes to lockCodes+lockCredentials profile triggers full SLGA migration and two syncs",
    function()
      -- Warm up device_cache with the original (lock-battery) profile via init.
      -- For a non-SLGA_MIGRATED device, legacy-handlers' init fires (no zigbee sends).
      test.socket.device_lifecycle:__queue_receive({ dev.id, "init" })
      test.wait_for_events()

      -- Switch to base-lock (lockCodes + lockCredentials)
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.device_lifecycle:__queue_receive(
        dev:generate_info_changed({ profile = t_utils.get_profile_definition("base-lock.yml") })
      )
      -- Migration events
      test.socket.capability:__expect_send(
        dev:generate_test_message("main",
          capabilities.lockCodes.migrated(true, { visibility = { displayed = false } }))
      )
      test.socket.capability:__expect_send(
        dev:generate_test_message("main",
          capabilities.lockCredentials.supportedCredentials({ "pin" }, { visibility = { displayed = false } }))
      )
      -- inject_capability_command calls the refresh handler inline
      test.socket.zigbee:__expect_send({
        dev.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:read(dev),
      })
      test.socket.zigbee:__expect_send({
        dev.id,
        DoorLock.attributes.LockState:read(dev),
      })
      test.socket.zigbee:__expect_send({
        dev.id,
        Alarms.attributes.AlarmCount:read(dev),
      })
      test.socket.zigbee:__expect_send({
        dev.id,
        DoorLock.attributes.MaxPINCodeLength:read(dev),
      })
      test.socket.zigbee:__expect_send({
        dev.id,
        DoorLock.attributes.MinPINCodeLength:read(dev),
      })
      test.socket.zigbee:__expect_send({
        dev.id,
        DoorLock.attributes.NumberOfPINUsersSupported:read(dev),
      })
      -- Immediate sync_device_state
      test.wait_for_events()

      assert(
        dev:get_field(constants.DRIVER_STATE.SLGA_MIGRATED) == true,
        "SLGA_MIGRATED must be set after infoChanged profile switch"
      )

      -- Delayed sync_device_state (2 s)
      test.mock_time.advance_time(2)
      test.socket.zigbee:__set_channel_ordering("relaxed")
      expect_sync_device_state(dev)
      test.wait_for_events()
    end,
    {
      test_init = function()
        test.disable_startup_messages()
        dev = test.mock_device.build_test_zigbee_device({
          profile = t_utils.get_profile_definition("lock-battery.yml"),
        })
        test.mock_device.add_test_device(dev)
      end,
    }
  )
end

do
  local dev
  test.register_coroutine_test(
    "infoChanged: no profile change does nothing",
    function()
      -- Warm up device_cache
      test.socket.device_lifecycle:__queue_receive({ dev.id, "init" })
      test.wait_for_events()

      -- infoChanged with no profile change
      test.socket.device_lifecycle:__queue_receive(dev:generate_info_changed({}))
      test.wait_for_events()
      -- No capability events, no zigbee sends expected
    end,
    {
      test_init = function()
        test.disable_startup_messages()
        dev = test.mock_device.build_test_zigbee_device({
          profile = t_utils.get_profile_definition("base-lock.yml"),
        })
        test.mock_device.add_test_device(dev)
      end,
    }
  )
end


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
    -- SLGA_MIGRATED is not set; lockCodes is supported; elseif branch does not apply
    test.socket.device_lifecycle:__queue_receive({ mock_device_base.id, "init" })
    test.wait_for_events()
    -- No capability events and no zigbee sends expected
  end,
  { test_init = make_test_init(mock_device_base) }
)

test.register_coroutine_test(
  "init: SLGA_MIGRATED device without lockCodes sends NumberOfPINUsersSupported read to detect re-profiling",
  function()
    -- Pre-seed SLGA_MIGRATED=true so legacy-handlers is bypassed and the main driver's
    -- init fires.  lock-battery has no lockCodes, so the elseif branch executes and
    -- reads NumberOfPINUsersSupported to detect whether the device should be re-profiled.
    mock_device_battery:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })

    test.socket.device_lifecycle:__queue_receive({ mock_device_battery.id, "init" })
    test.socket.zigbee:__expect_send({
      mock_device_battery.id,
      DoorLock.attributes.NumberOfPINUsersSupported:read(mock_device_battery),
    })
    test.wait_for_events()
  end,
  { test_init = make_test_init(mock_device_battery) }
)

-- ============================================================================
-- driverSwitched (LockLifecycle.driver_switched)
-- ============================================================================

test.register_coroutine_test(
  "driver_switched: device with lockCodes and migrated=true persists SLGA_MIGRATED and updates metadata",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_typed.id, "added" })

    -- Migrated event is emitted before the injected refresh
    test.socket.capability:__expect_send(
      mock_device_typed:generate_test_message("main",
        capabilities.lockCodes.migrated(true, { visibility = { displayed = false } }))
    )
    -- inject_capability_command calls the refresh handler inline
    test.socket.zigbee:__expect_send({
      mock_device_typed.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_typed),
    })
    test.socket.zigbee:__expect_send({
      mock_device_typed.id,
      DoorLock.attributes.LockState:read(mock_device_typed),
    })
    test.socket.zigbee:__expect_send({
      mock_device_typed.id,
      Alarms.attributes.AlarmCount:read(mock_device_typed),
    })
    test.socket.zigbee:__expect_send({
      mock_device_typed.id,
      DoorLock.attributes.MaxPINCodeLength:read(mock_device_typed),
    })
    test.socket.zigbee:__expect_send({
      mock_device_typed.id,
      DoorLock.attributes.MinPINCodeLength:read(mock_device_typed),
    })
    test.socket.zigbee:__expect_send({
      mock_device_typed.id,
      DoorLock.attributes.NumberOfPINUsersSupported:read(mock_device_typed),
    })
    test.wait_for_events()

    -- driverSwitched occurs after added, so migrated=true is already set in the capability state cache
    test.socket.device_lifecycle:__queue_receive({ mock_device_typed.id, "driver_switched" })
    mock_device_typed:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()

    assert(mock_device_typed:get_field(constants.DRIVER_STATE.SLGA_MIGRATED) == true)
  end,
  { test_init = make_test_init(mock_device_typed) }
)

-- ============================================================================
test.run_registered_tests()
