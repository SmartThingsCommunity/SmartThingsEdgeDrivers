-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local z_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local can_handle = require "zemismart.can_handle"
local helpers = require "test.zemismart_feedback_test_utils"

local device = helpers.create()
local battery_device = helpers.create("window-treatment-battery.yml")
local fresh_device, fresh_fingerprint = helpers.create_from_fingerprint()
local shade = capabilities.windowShade.windowShade
helpers.set_test_init(device)

local function expect_position(level, state)
  helpers.expect_event(capabilities.windowShadeLevel.shadeLevel(level))
  helpers.expect_event(state)
end

local function report_then_settle(level, movement)
  helpers.report(level)
  expect_position(level, movement)
  test.wait_for_events()
  helpers.expect_event(shade.partially_open())
  helpers.advance(2)
end

test.register_coroutine_test("Shared fingerprint handles both existing profiles without matching unrelated devices", function()
  assert(can_handle(nil, nil, device))
  for _, pair in ipairs({ { "different", "TS0301" }, { "_TZE200_cirjrpxe", "different" } }) do
    assert(not can_handle(nil, nil, {
      get_manufacturer = function() return pair[1] end,
      get_model = function() return pair[2] end,
    }))
  end
end)

for _, entry in ipairs({ { "non-battery", device }, { "battery", battery_device } }) do
  test.register_coroutine_test("Driver switch accepts the " .. entry[1] .. " profile", function()
    assert(can_handle(nil, nil, entry[2]))
    test.socket.device_lifecycle:__queue_receive({ entry[2].id, "driverSwitched" })
    entry[2]:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end, { test_init = function() helpers.initialize_device(entry[2]) end })
end

test.register_coroutine_test("Non-battery profile ignores unsupported battery reports", function()
  for _, attr in ipairs({ clusters.PowerConfiguration.attributes.BatteryVoltage,
      clusters.PowerConfiguration.attributes.BatteryPercentageRemaining }) do
    test.socket.zigbee:__queue_receive({ device.id, attr:build_test_attr_report(device, 100) })
    test.wait_for_events()
  end
  assert(device:get_latest_state("main", "battery", "battery") == nil)
end)

test.register_coroutine_test("Battery profile retains standard percentage and voltage reports", function()
  test.socket.zigbee:__queue_receive({ battery_device.id,
    clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(battery_device, 150) })
  helpers.expect_event(capabilities.battery.battery(75), battery_device)
  test.wait_for_events()
  battery_device:set_field(battery_defaults.DEVICE_MIN_VOLTAGE_KEY, 2.0)
  battery_device:set_field(battery_defaults.DEVICE_MAX_VOLTAGE_KEY, 3.0)
  test.socket.zigbee:__queue_receive({ battery_device.id,
    clusters.PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(battery_device, 25) })
  helpers.expect_event(capabilities.battery.battery(50), battery_device)
end, { test_init = function() helpers.initialize_device(battery_device) end })

test.register_coroutine_test("Configuration and refresh preserve standard position reporting", function()
  test.socket.device_lifecycle:__queue_receive({ device.id, "doConfigure" })
  test.socket.zigbee:__set_channel_ordering("relaxed")
  helpers.expect_read()
  test.socket.zigbee:__expect_send({ device.id,
    z_utils.build_bind_request(device, z_utils.mock_hub_eui, clusters.WindowCovering.ID) })
  test.socket.zigbee:__expect_send({ device.id,
    clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:configure_reporting(device, 0, 600, 1) })
  device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  test.wait_for_events()
  helpers.command("refresh", "refresh")
  helpers.expect_read()
end)

test.register_coroutine_test("Added announces supported commands without manufacturing Unknown", function()
  test.socket.device_lifecycle:__queue_receive({ device.id, "added" })
  helpers.expect_event(capabilities.windowShade.supportedWindowShadeCommands(
    { "open", "close", "pause" }, { visibility = { displayed = false } }))
end)

test.register_coroutine_test("Preset storage and movement retain standard semantics", function()
  helpers.seed(43)
  helpers.command("windowShadePreset", "setPresetPosition", { 40 })
  helpers.expect_event(capabilities.windowShadePreset.position(40))
  test.wait_for_events()
  helpers.command("windowShadePreset", "presetPosition")
  helpers.expect_motion("GoToLiftPercentage", 40)
  test.wait_for_events()
  assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == 43)
  report_then_settle(40, shade.closing())
end)

test.register_coroutine_test("Absolute control does not optimistically change reported position", function()
  helpers.seed(43)
  helpers.command("windowShadeLevel", "setShadeLevel", { 75 })
  helpers.expect_motion("GoToLiftPercentage", 75)
  test.wait_for_events()
  assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == 43)
  report_then_settle(75, shade.opening())
end)

test.register_coroutine_test("Absolute movement ends the prior relative-step sequence", function()
  helpers.seed(50)
  helpers.step(10, 60)
  report_then_settle(60, shade.opening())
  helpers.command("windowShadeLevel", "setShadeLevel", { 50 })
  helpers.expect_motion("GoToLiftPercentage", 50)
  test.wait_for_events()
  report_then_settle(50, shade.closing())
  helpers.step(-10, 40)
end, { min_api_version = 15 })

test.register_coroutine_test("Rapid relative steps accumulate despite intermediate reports", function()
  helpers.seed(50)
  helpers.step(10, 60)
  helpers.report(52)
  expect_position(52, shade.opening())
  test.wait_for_events()
  helpers.step(-5, 55)
  helpers.step(15, 70)
end, { min_api_version = 15 })

for _, action in ipairs({
  { "windowShade", "open", "UpOrOpen" },
  { "windowShade", "close", "DownOrClose" },
  { "windowShade", "pause", "Stop" },
  { "windowShadePreset", "presetPosition", "GoToLiftPercentage", 50 },
}) do
  test.register_coroutine_test(action[2] .. " clears the previous step target without changing position", function()
    helpers.seed(51)
    helpers.step(10, 61)
    helpers.command(action[1], action[2])
    helpers.expect_motion(action[3], action[4])
    test.wait_for_events()
    helpers.step(-10, 41)
  end, { min_api_version = 15 })
end

test.register_coroutine_test("Refresh and preset setting preserve rapid step accumulation", function()
  helpers.seed(50)
  helpers.step(10, 60)
  helpers.command("refresh", "refresh")
  helpers.expect_read()
  test.wait_for_events()
  helpers.command("windowShadePreset", "setPresetPosition", { 40 })
  helpers.expect_event(capabilities.windowShadePreset.position(40))
  test.wait_for_events()
  helpers.step(-5, 55)
end, { min_api_version = 15 })

test.register_coroutine_test("Expired step accumulation starts from the latest real position", function()
  helpers.seed(50)
  helpers.step(10, 60)
  helpers.advance(16)
  helpers.step(-5, 45)
end, { min_api_version = 15 })

test.register_coroutine_test("Interrupted step timeout cannot clear a newer step sequence", function()
  helpers.seed(50)
  local callbacks, restore = helpers.capture_callbacks()
  helpers.step(10, 60)
  restore()
  helpers.advance(5)
  helpers.command("windowShade", "pause")
  helpers.expect_motion("Stop")
  test.wait_for_events()
  helpers.step(-10, 40)
  callbacks[1].callback()
  test.wait_for_events()
  helpers.advance(11)
  helpers.step(5, 45)
end, { min_api_version = 15 })

for _, entry in ipairs({ { 95, 10, 100 }, { 5, -10, 0 } }) do
  test.register_coroutine_test("Relative step clamps at endpoint " .. entry[3], function()
    helpers.seed(entry[1])
    helpers.step(entry[2], entry[3])
  end, { min_api_version = 15 })
end

test.register_coroutine_test("Zero step sends nothing from an ordinary static position", function()
  helpers.seed(43)
  helpers.command("statelessWindowShadeLevelStep", "stepShadeLevel", { 0 })
  test.wait_for_events()
  assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == 43)
end)

test.register_coroutine_test("Zero step leaves an active relative sequence intact", function()
  helpers.seed(50)
  helpers.step(10, 60)
  helpers.command("statelessWindowShadeLevelStep", "stepShadeLevel", { 0 })
  test.wait_for_events()
  helpers.step(-5, 55)
end, { min_api_version = 15 })

test.register_coroutine_test("Failed step injection does not contaminate the next real command", function()
  helpers.seed(50)
  local handler = (require "zemismart").capability_handlers.statelessWindowShadeLevelStep.stepShadeLevel
  local ok, err = pcall(handler, {
    inject_capability_command = function() error("simulated dispatch failure") end,
  }, device, { component = "main", args = { stepSize = 10 } })
  assert(not ok and string.find(err, "simulated dispatch failure", 1, true))
  helpers.step(-5, 45)
end, { min_api_version = 15 })

test.register_coroutine_test("Removed device cannot be touched by a queued step callback", function()
  helpers.seed(50)
  local callbacks, restore = helpers.capture_callbacks()
  helpers.step(10, 60)
  restore()
  test.socket.device_lifecycle:__queue_receive({ device.id, "removed" })
  test.wait_for_events()
  for _, entry in ipairs(callbacks) do
    local ok, err = pcall(entry.callback)
    assert(ok, "callback touched deleted device: " .. tostring(err))
  end
  helpers.advance(16)
end, { min_api_version = 15 })


-- These devices come from the real package fingerprint, not a hard-coded test profile.
-- Hub/cloud selection and physical onboarding remain separate acceptance checks.
local function fresh_init()
  helpers.initialize_device(fresh_device)
end

test.register_coroutine_test("Package fingerprint selects one compatible profile with all shade capabilities", function()
  assert(fresh_fingerprint.deviceProfileName == "window-treatment-battery")
  assert(not string.find(fresh_fingerprint.deviceLabel, "ZM25Z", 1, true), "shared identity must not claim a unique SKU")
  assert(can_handle(nil, nil, fresh_device))
  for _, id in ipairs({ "windowShade", "windowShadePreset", "windowShadeLevel", "statelessWindowShadeLevelStep",
      "battery", "firmwareUpdate", "refresh" }) do
    assert(fresh_device:supports_capability_by_id(id), "selected profile missing " .. id)
  end
end, { test_init = fresh_init })

test.register_coroutine_test("Fingerprint-selected profile configures shade and battery reporting", function()
  test.socket.device_lifecycle:__queue_receive({ fresh_device.id, "doConfigure" })
  test.socket.zigbee:__set_channel_ordering("relaxed")
  helpers.expect_read(fresh_device)
  test.socket.zigbee:__expect_send({ fresh_device.id,
    clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:read(fresh_device) })
  for _, cluster in ipairs({ clusters.WindowCovering, clusters.PowerConfiguration }) do
    test.socket.zigbee:__expect_send({ fresh_device.id,
      z_utils.build_bind_request(fresh_device, z_utils.mock_hub_eui, cluster.ID) })
  end
  test.socket.zigbee:__expect_send({ fresh_device.id,
    clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:configure_reporting(fresh_device, 0, 600, 1) })
  test.socket.zigbee:__expect_send({ fresh_device.id,
    clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(fresh_device, 30, 21600, 1) })
  fresh_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end, { test_init = fresh_init })

test.register_coroutine_test("Fingerprint-selected refresh reads position and battery and preserves real responses", function()
  helpers.command("refresh", "refresh", nil, fresh_device)
  test.socket.zigbee:__set_channel_ordering("relaxed")
  helpers.expect_read(fresh_device)
  test.socket.zigbee:__expect_send({ fresh_device.id,
    clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:read(fresh_device) })
  test.wait_for_events()
  helpers.response(43, fresh_device)
  helpers.expect_static(43, fresh_device)
  test.wait_for_events()
  test.socket.zigbee:__queue_receive({ fresh_device.id,
    clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_read_attr_response(fresh_device, 200) })
  helpers.expect_event(capabilities.battery.battery(100), fresh_device)
  test.wait_for_events()
  test.socket.zigbee:__queue_receive({ fresh_device.id,
    clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(fresh_device, 150) })
  helpers.expect_event(capabilities.battery.battery(75), fresh_device)
end, { test_init = fresh_init })

test.register_coroutine_test("Fingerprint-selected profile keeps preset and relative control after Unknown", function()
  helpers.seed(43, fresh_device)
  helpers.report(0xFF, fresh_device)
  helpers.expect_event(shade.unknown(), fresh_device)
  test.wait_for_events()
  helpers.command("windowShadePreset", "setPresetPosition", { 50 }, fresh_device)
  helpers.expect_event(capabilities.windowShadePreset.position(50), fresh_device)
  test.wait_for_events()
  helpers.command("windowShadePreset", "presetPosition", nil, fresh_device)
  helpers.expect_motion("GoToLiftPercentage", 50, fresh_device)
  test.wait_for_events()
  helpers.response(50, fresh_device)
  helpers.expect_static(50, fresh_device)
  test.wait_for_events()
  helpers.step(-10, 40, fresh_device)
end, { test_init = fresh_init, min_api_version = 15 })

test.run_registered_tests()
