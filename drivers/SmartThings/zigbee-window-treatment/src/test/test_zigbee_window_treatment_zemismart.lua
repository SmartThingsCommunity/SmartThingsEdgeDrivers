-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local z_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local can_handle = require "zemismart.can_handle"

local function build_device(profile)
  return test.mock_device.build_test_zigbee_device({
    profile = t_utils.get_profile_definition(profile),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "_TZE200_cirjrpxe",
        model = "TS0301",
        server_clusters = { 0x0000, 0x0001, 0x0003, 0x0004, 0x0005, 0x0102, 0xEF00 },
        client_clusters = { 0x0019 },
      },
    },
  })
end

local mock_device = build_device("window-treatment-profile.yml")
local battery_device = build_device("window-treatment-battery.yml")

local function expect_event(device, event)
  test.socket.capability:__expect_send(device:generate_test_message("main", event))
end

local function initialize_device(device)
  test.mock_device.add_test_device(device)
  expect_event(device, capabilities.windowShadePreset.supportedCommands(
    { "presetPosition", "setPresetPosition" }, { visibility = { displayed = false } }))
  expect_event(device, capabilities.windowShadePreset.position(
    50, { visibility = { displayed = false } }))
  if device == mock_device then
    expect_event(device, capabilities.windowShade.windowShade.unknown())
    test.socket.zigbee:__expect_send({ device.id,
      clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:read(device) })
  end
end

local function command(capability, name, args)
  test.socket.capability:__queue_receive({ mock_device.id, {
    capability = capability, component = "main", command = name, args = args or {},
  } })
end

local function expect_position_read()
  test.socket.zigbee:__expect_send({ mock_device.id,
    clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:read(mock_device) })
end

local sequence = 0
local function read_response(level)
  sequence = (sequence + 1) % 256
  local message = clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:
    build_test_read_attr_response(mock_device, level)
  message.body.zcl_header.seqno.value = sequence
  test.socket.zigbee:__queue_receive({ mock_device.id, message })
end

local function confirm_position(level)
  assert(mock_device:get_field("_zemismartMotionContext") == nil)
  if mock_device:get_field("_zemismartPositionCheck") == nil then
    command("refresh", "refresh")
    expect_position_read()
    test.wait_for_events()
  end
  local was_trusted = (require "zemismart.position_confirmation").position_is_known(mock_device)
  local previous = mock_device:get_latest_state("main", "windowShadeLevel", "shadeLevel")
  test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
  read_response(level)
  if was_trusted and previous ~= level then
    expect_event(mock_device, capabilities.windowShade.windowShade.unknown())
  end
  test.wait_for_events()
  test.mock_time.advance_time(2)
  expect_position_read()
  test.wait_for_events()
  read_response(level)
  expect_event(mock_device, capabilities.windowShadeLevel.shadeLevel(level))
  expect_event(mock_device, level == 0 and capabilities.windowShade.windowShade.closed()
    or level == 100 and capabilities.windowShade.windowShade.open()
    or capabilities.windowShade.windowShade.partially_open())
  test.wait_for_events()
  assert((require "zemismart.position_confirmation").position_is_known(mock_device))
end

local function report_level(level)
  local motion = mock_device:get_field("_zemismartMotionContext")
  if not motion then confirm_position(level); return end
  test.socket.zigbee:__queue_receive({ mock_device.id,
    clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(
      mock_device, level) })
  if level == motion.target then
    expect_event(mock_device, capabilities.windowShade.windowShade.unknown())
    expect_position_read()
    test.wait_for_events()
    confirm_position(level)
  else
    expect_event(mock_device, capabilities.windowShadeLevel.shadeLevel(level))
    expect_event(mock_device, level > motion.last and capabilities.windowShade.windowShade.opening()
      or capabilities.windowShade.windowShade.closing())
    test.wait_for_events()
  end
end

local function step_and_expect(step, target)
  local new_check = mock_device:get_field("_zemismartPositionCheck") == nil
  command("statelessWindowShadeLevelStep", "stepShadeLevel", { step })
  test.socket.zigbee:__expect_send({ mock_device.id,
    clusters.WindowCovering.server.commands.GoToLiftPercentage(mock_device, target) })
  if new_check then expect_position_read() end
  test.wait_for_events()
end

z_utils.prepare_zigbee_env_info()
test.set_test_init_function(function() initialize_device(mock_device) end)

test.register_coroutine_test("Battery suppression is restricted to the non-battery target", function()
  assert(can_handle(nil, nil, mock_device))
  assert(not can_handle(nil, nil, {
    get_manufacturer = function() return "_TZE200_cirjrpxe" end,
    get_model = function() return "TS0301" end,
    supports_capability_by_id = function(_, id) return id == capabilities.battery.ID end,
  }))
  assert(not can_handle(nil, nil, {
    get_manufacturer = function() return "different_manufacturer" end,
    get_model = function() return "TS0301" end,
  }))
  assert(not can_handle(nil, nil, {
    get_manufacturer = function() return "_TZE200_cirjrpxe" end,
    get_model = function() return "different_model" end,
  }))
end)

test.register_coroutine_test("Target driver switch accepts the official non-battery profile", function()
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "driverSwitched" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end)

test.register_coroutine_test("Unsolicited battery reports do not attempt unsupported events", function()
  local original_emit = mock_device.emit_event_for_endpoint
  mock_device.emit_event_for_endpoint = function(self, endpoint, event)
    assert(event.capability.ID ~= capabilities.battery.ID, "Unexpected battery event attempt")
    return original_emit(self, endpoint, event)
  end
  for _, attribute in ipairs({ clusters.PowerConfiguration.attributes.BatteryVoltage,
      clusters.PowerConfiguration.attributes.BatteryPercentageRemaining }) do
    test.socket.zigbee:__queue_receive({ mock_device.id,
      attribute:build_test_attr_report(mock_device, 100) })
    test.wait_for_events()
  end
  assert(mock_device:get_latest_state("main", capabilities.battery.ID, "battery") == nil)
  mock_device.emit_event_for_endpoint = original_emit
end)

test.register_coroutine_test("Configuration and refresh read position without battery traffic", function()
  confirm_position(50)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  test.socket.zigbee:__set_channel_ordering("relaxed")
  expect_position_read()
  test.socket.zigbee:__expect_send({ mock_device.id,
    z_utils.build_bind_request(mock_device, z_utils.mock_hub_eui, clusters.WindowCovering.ID) })
  test.socket.zigbee:__expect_send({ mock_device.id,
    clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:configure_reporting(
      mock_device, 0, 600, 1) })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  test.wait_for_events()
  command("refresh", "refresh") -- Coalesces with the configuration read already in flight.
  test.wait_for_events()
  confirm_position(50)
  command("refresh", "refresh")
  expect_position_read()
end)

test.register_coroutine_test("Target open close and pause retain standard commands", function()
  confirm_position(50)
  for i, pair in ipairs({ { "open", "UpOrOpen" }, { "close", "DownOrClose" },
      { "pause", "Stop" } }) do
    command("windowShade", pair[1])
    test.socket.zigbee:__expect_send({ mock_device.id,
      clusters.WindowCovering.server.commands[pair[2]](mock_device) })
    if i == 1 or i == 3 then expect_position_read() end
    if i == 3 then expect_event(mock_device, capabilities.windowShade.windowShade.unknown()) end
    test.wait_for_events()
  end
  assert(mock_device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == 50)
end)

test.register_coroutine_test("Target level control and actual position reports are unchanged", function()
  confirm_position(43)
  for _, level in ipairs({ 25, 75, 50, 0, 100 }) do
    local previous = mock_device:get_latest_state("main", "windowShadeLevel", "shadeLevel")
    command("windowShadeLevel", "setShadeLevel", { level })
    test.socket.zigbee:__expect_send({ mock_device.id,
      clusters.WindowCovering.server.commands.GoToLiftPercentage(mock_device, level) })
    expect_position_read()
    test.wait_for_events()
    assert(mock_device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == previous)
    report_level(math.floor((previous + level) / 2))
    report_level(level)
  end
end)

test.register_coroutine_test("Target preset and relative step retain standard commands", function()
  confirm_position(50)
  command("windowShadePreset", "setPresetPosition", { 40 })
  expect_event(mock_device, capabilities.windowShadePreset.position(40))
  test.wait_for_events()
  command("windowShadePreset", "presetPosition")
  test.socket.zigbee:__expect_send({ mock_device.id,
    clusters.WindowCovering.server.commands.GoToLiftPercentage(mock_device, 40) })
  expect_position_read()
  test.wait_for_events()
  report_level(45)
  report_level(40)
  step_and_expect(10, 50)
end)

test.register_coroutine_test("Existing battery profiles retain percentage and voltage reporting", function()
  test.socket.zigbee:__queue_receive({ battery_device.id,
    clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(
      battery_device, 150) })
  expect_event(battery_device, capabilities.battery.battery(75))
  test.wait_for_events()
  battery_device:set_field(battery_defaults.DEVICE_MIN_VOLTAGE_KEY, 2.0)
  battery_device:set_field(battery_defaults.DEVICE_MAX_VOLTAGE_KEY, 3.0)
  test.socket.zigbee:__queue_receive({ battery_device.id,
    clusters.PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(battery_device, 25) })
  expect_event(battery_device, capabilities.battery.battery(50))
end, { test_init = function() initialize_device(battery_device) end })

test.register_coroutine_test("Absolute movement ends the previous relative-step sequence", function()
  report_level(51)
  step_and_expect(10, 61)
  report_level(61)
  command("windowShadeLevel", "setShadeLevel", { 50 })
  test.socket.zigbee:__expect_send({ mock_device.id,
    clusters.WindowCovering.server.commands.GoToLiftPercentage(mock_device, 50) })
  expect_position_read()
  test.wait_for_events()
  report_level(50)
  step_and_expect(-10, 40)
end)

test.register_coroutine_test("Rapid relative steps accumulate despite intermediate reports", function()
  report_level(50)
  step_and_expect(10, 60)
  report_level(52)
  step_and_expect(-5, 55)
  step_and_expect(15, 70)
end)

local motion_commands = {
  { name = "open", capability = "windowShade", zigbee = "UpOrOpen", actual = 70 },
  { name = "close", capability = "windowShade", zigbee = "DownOrClose", actual = 30 },
  { name = "pause", capability = "windowShade", zigbee = "Stop", actual = 55 },
  { name = "presetPosition", capability = "windowShadePreset",
    zigbee = "GoToLiftPercentage", actual = 50, target = 50 },
}

for _, motion in ipairs(motion_commands) do
  test.register_coroutine_test(motion.name .. " ends the previous relative-step sequence", function()
    report_level(51)
    step_and_expect(10, 61)
    command(motion.capability, motion.name)
    test.socket.zigbee:__expect_send({ mock_device.id,
      clusters.WindowCovering.server.commands[motion.zigbee](mock_device, motion.target) })
    if motion.name == "pause" then
      expect_position_read()
      expect_event(mock_device, capabilities.windowShade.windowShade.unknown())
    end
    test.wait_for_events()
    report_level(motion.actual)
    step_and_expect(-10, motion.actual - 10)
  end)
end

test.register_coroutine_test("Refresh and preset configuration preserve relative-step accumulation",
  function()
    report_level(50)
    step_and_expect(10, 60)
    command("refresh", "refresh")
    test.wait_for_events()
    command("windowShadePreset", "setPresetPosition", { 40 })
    expect_event(mock_device, capabilities.windowShadePreset.position(40))
    test.wait_for_events()
    step_and_expect(-5, 55)
  end)

test.register_coroutine_test("Interrupted step timers cannot clear a later sequence", function()
  report_level(50)
  test.timer.__create_and_queue_test_time_advance_timer(15, "oneshot")
  step_and_expect(10, 60)
  test.mock_time.advance_time(5)
  test.wait_for_events()
  command("windowShade", "pause")
  test.socket.zigbee:__expect_send({ mock_device.id,
    clusters.WindowCovering.server.commands.Stop(mock_device) })
  expect_position_read()
  expect_event(mock_device, capabilities.windowShade.windowShade.unknown())
  test.wait_for_events()
  assert(mock_device:get_field("_latestTargetLevel") == nil)
  assert(mock_device:get_field("_targetLevelTimeOut") == nil)
  confirm_position(50)
  test.timer.__create_and_queue_test_time_advance_timer(15, "oneshot")
  step_and_expect(-10, 40)
  test.mock_time.advance_time(11)
  test.wait_for_events()
  assert(mock_device:get_field("_latestTargetLevel") == 40)
  test.mock_time.advance_time(5)
  test.wait_for_events()
  assert(mock_device:get_field("_latestTargetLevel") == nil)
  assert(mock_device:get_field("_targetLevelTimeOut") == nil)
  command("windowShadeLevel", "setShadeLevel", { 45 })
  test.socket.zigbee:__expect_send({ mock_device.id,
    clusters.WindowCovering.server.commands.GoToLiftPercentage(mock_device, 45) })
  test.wait_for_events()
  report_level(45)
  step_and_expect(-5, 40)
end)

test.register_coroutine_test("Zero relative steps preserve the sequence and clear the dispatch marker",
  function()
    report_level(50)
    step_and_expect(10, 60)
    command("statelessWindowShadeLevelStep", "stepShadeLevel", { 0 })
    test.wait_for_events()
    assert(mock_device:get_field("_latestTargetLevel") == 60)
    assert(mock_device:get_field("_zemismartStepDispatch") == nil)
    step_and_expect(-5, 55)
  end)

test.register_coroutine_test("Failed internal step dispatch leaves no stale target or marker", function()
  report_level(50)
  local step_handler = (require "zemismart").capability_handlers[
    capabilities.statelessWindowShadeLevelStep.ID][
    capabilities.statelessWindowShadeLevelStep.commands.stepShadeLevel.NAME]
  expect_event(mock_device, capabilities.windowShade.windowShade.unknown())
  local ok, err = pcall(step_handler, {
    inject_capability_command = function() error("simulated dispatch failure") end,
  }, mock_device, { component = "main", args = { stepSize = 10 } })
  assert(not ok and string.find(err, "simulated dispatch failure", 1, true))
  assert(mock_device:get_field("_zemismartStepDispatch") == nil)
  assert(mock_device:get_field("_latestTargetLevel") == nil)
  assert(mock_device:get_field("_targetLevelTimeOut") == nil)
  confirm_position(50)
  command("windowShadeLevel", "setShadeLevel", { 30 })
  test.socket.zigbee:__expect_send({ mock_device.id,
    clusters.WindowCovering.server.commands.GoToLiftPercentage(mock_device, 30) })
  expect_position_read()
end)

test.run_registered_tests()
