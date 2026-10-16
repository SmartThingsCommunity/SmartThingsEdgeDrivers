-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local Status = require "st.zigbee.generated.types.ZclStatus"
local confirmation = require "zemismart.position_confirmation"
local shade_utils = require "window_shade_utils"
local helpers = require "test.zemismart_feedback_test_utils"

local device = helpers.create()
local battery_device = helpers.create("window-treatment-battery.yml")
local shade = capabilities.windowShade.windowShade
local window = clusters.WindowCovering
local CHECK = "_zemismartPositionCheck"
local MOTION = "_zemismartMotionContext"

helpers.set_test_init(device)

local function is_unknown()
  assert(not confirmation.position_is_known(device), "position must remain untrusted")
  assert(device:get_latest_state("main", "windowShade", "windowShade") == "unknown")
end

local function expect_motion(command, argument)
  local message = argument ~= nil and window.server.commands[command](device, argument)
    or window.server.commands[command](device)
  test.socket.zigbee:__expect_send({ device.id, message })
end

local function start_refresh()
  helpers.command("refresh", "refresh")
  helpers.expect_read()
  test.wait_for_events()
end

local function make_unknown()
  helpers.report(0xFF, 0x70)
  helpers.expect_event(shade.unknown())
  helpers.expect_read()
  test.wait_for_events()
  is_unknown()
end

local function next_read(seconds)
  helpers.expect_read()
  helpers.advance(seconds or 2)
end

local function finish_response(level, sequence)
  helpers.response(level, sequence)
  helpers.expect_static(level)
  test.wait_for_events()
  assert(confirmation.position_is_known(device))
end

local function capture_delayed_callbacks()
  local original = device.thread.call_with_delay
  local callbacks = {}
  device.thread.call_with_delay = function(thread, seconds, callback, ...)
    callbacks[#callbacks + 1] = { seconds = seconds, callback = callback }
    return original(thread, seconds, callback, ...)
  end
  return callbacks, function() device.thread.call_with_delay = original end
end

local function callback_for(callbacks, seconds)
  for _, entry in ipairs(callbacks) do
    if entry.seconds == seconds then return entry.callback end
  end
  error("requested callback was not scheduled")
end

test.register_coroutine_test("Startup requires reads instead of trusting a cached percentage", function()
  is_unknown()
  assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == nil)
  assert(device:get_field(CHECK).reads == 1)
  helpers.report(43, 3)
  test.wait_for_events()
  is_unknown()
  assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == nil)
end)

for _, level in ipairs({ 0, 43, 100 }) do
  test.register_coroutine_test("Two separated successful reads establish static " .. level, function()
    helpers.confirm(level)
    assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == level)
    assert(device:get_field(CHECK) == nil)
    helpers.advance(35)
  end)
end

test.register_coroutine_test("H03 reports at 0, 0.576, 4.750 seconds cannot establish startup trust",
  function()
    helpers.report(43, 3)
    test.wait_for_events()
    helpers.advance(0.576)
    helpers.report(0, 0)
    test.wait_for_events()
    helpers.advance(4.174)
    helpers.report(43, 8)
    test.wait_for_events()
    is_unknown()
    assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == nil)
    assert(device:get_field(CHECK).reads == 1)
  end)

test.register_coroutine_test("H03 recovery sequence never emits zero closed opening or motion", function()
  helpers.confirm(43)
  make_unknown()
  helpers.report(43, 3)
  test.wait_for_events()
  helpers.advance(0.576)
  helpers.report(0, 0)
  test.wait_for_events()
  helpers.advance(4.174)
  helpers.report(43, 8)
  test.wait_for_events()
  is_unknown()
  assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == 43)
  assert(device:get_field(CHECK).observations == 0)
end)

for _, level in ipairs({ 0, 43, 100 }) do
  test.register_coroutine_test("Unknown recovery needs two static reads at " .. level, function()
    helpers.confirm(43)
    make_unknown()
    helpers.confirm(level, 0, 0xFF)
    assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == level)
    helpers.advance(35)
  end)
end

test.register_coroutine_test("Two replies in one read round count only once", function()
  helpers.response(43, 1)
  test.wait_for_events()
  helpers.response(43, 2)
  test.wait_for_events()
  is_unknown()
  assert(device:get_field(CHECK).observations == 1)
  next_read()
  finish_response(43, 2)
end)

test.register_coroutine_test("Repeated sequence in a later round does not establish trust", function()
  helpers.response(43, 0)
  test.wait_for_events()
  next_read()
  helpers.response(43, 0)
  test.wait_for_events()
  is_unknown()
  assert(device:get_field(CHECK).observations == 1)
  assert(device:get_field(CHECK).pending)
  finish_response(43, 0xFF)
end)

test.register_coroutine_test("Sequence FF to 00 is allowed without ordering assumptions", function()
  helpers.confirm(43, 0xFF, 0)
end)

test.register_coroutine_test("Sequence de-duplication resets with a genuinely new session", function()
  helpers.confirm(43, 0, 1)
  make_unknown()
  helpers.confirm(43, 0, 1)
end)

test.register_coroutine_test("Replies outside any active read session cannot replace trusted position",
  function()
    helpers.confirm(43)
    helpers.response(0, 0x44)
    helpers.response(100, 0x45)
    test.wait_for_events()
    assert(confirmation.position_is_known(device))
    assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == 43)
    assert(device:get_latest_state("main", "windowShade", "windowShade") == "partially open")
  end)

test.register_coroutine_test("A contradictory report invalidates the first read observation", function()
  helpers.response(43, 1)
  test.wait_for_events()
  helpers.report(0, 0)
  test.wait_for_events()
  assert(device:get_field(CHECK).observations == 0)
  next_read()
  helpers.response(43, 2)
  test.wait_for_events()
  is_unknown()
  next_read()
  finish_response(43, 3)
end)

test.register_coroutine_test("Mismatching static replies need a new agreeing observation", function()
  helpers.response(43, 1)
  test.wait_for_events()
  next_read()
  helpers.response(44, 2)
  test.wait_for_events()
  is_unknown()
  next_read()
  finish_response(44, 3)
end)

test.register_coroutine_test("Three mutually inconsistent replies exhaust the static read count", function()
  for round, level in ipairs({ 43, 0, 43 }) do
    helpers.response(level, round)
    test.wait_for_events()
    if round < 3 then next_read() end
  end
  helpers.advance(2)
  is_unknown()
  assert(device:get_field(CHECK) == nil)
  assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == nil)
end)

test.register_coroutine_test("Wrong endpoint and failed read status cannot confirm the position", function()
  helpers.response(43, 1, 2)
  helpers.report(43, 2, 2)
  local failed = helpers.response(43, 3)
  failed.body.zcl_body.attr_records[1].status.value = Status.UNSUPPORTED_ATTRIBUTE
  test.socket.zigbee:__queue_receive({ device.id,
    clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(
      device, 200) })
  test.wait_for_events()
  is_unknown()
  assert(device:get_field(CHECK).observations == 0)
  helpers.confirm(43, 4, 5)
end)

for _, level in ipairs({ 0xFF, 101, 254 }) do
  for _, kind in ipairs({ "response", "report" }) do
    test.register_coroutine_test("Invalid position " .. level .. " in " .. kind .. " revokes trust",
      function()
        helpers.confirm(43)
        helpers[kind](level, 1)
        helpers.expect_event(shade.unknown())
        helpers.expect_read()
        test.wait_for_events()
        is_unknown()
        assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == 43)
        helpers.confirm(43, 2, 3)
      end)
  end
end

test.register_coroutine_test("Only three unanswered reads fit the original thirty second budget", function()
  next_read(10)
  next_read(10)
  helpers.advance(9)
  assert(device:get_field(CHECK) ~= nil)
  helpers.advance(1)
  is_unknown()
  assert(device:get_field(CHECK) == nil)
  helpers.response(43, 0x55)
  helpers.advance(20)
  is_unknown()
  assert(device:get_field(CHECK) == nil)
end)

test.register_coroutine_test("A first reply at twenty-nine seconds cannot extend the hard budget", function()
  next_read(10)
  next_read(10)
  helpers.advance(9)
  helpers.response(43, 1)
  test.wait_for_events()
  is_unknown()
  assert(device:get_field(CHECK).observations == 1)
  helpers.advance(1)
  assert(device:get_field(CHECK) == nil)
  helpers.response(43, 2)
  test.wait_for_events()
  is_unknown()
  assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == nil)
end)

test.register_coroutine_test("Repeated refresh and report storms do not extend a static session", function()
  for second = 1, 29 do
    helpers.command("refresh", "refresh")
    helpers.report(second % 2 == 0 and 43 or 0, second % 256)
    test.wait_for_events()
    if second == 10 or second == 20 then helpers.expect_read() end
    helpers.advance(1)
  end
  helpers.advance(1)
  is_unknown()
  assert(device:get_field(CHECK) == nil)
  assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == nil)
end)

test.register_coroutine_test("Passive recovery cannot loop forever under an unsolicited report storm",
  function()
    next_read(10)
    next_read(10)
    helpers.advance(10)
    helpers.report(43, 1)
    helpers.expect_read()
    test.wait_for_events()
    next_read(10)
    next_read(10)
    helpers.advance(10)
    for sequence = 2, 20 do helpers.report(43, sequence) end
    helpers.advance(60)
    is_unknown()
    assert(device:get_field(CHECK) == nil)
  end)

test.register_coroutine_test("An old round callback cannot consume or end the next round", function()
  helpers.confirm(43)
  local callbacks, restore = capture_delayed_callbacks()
  start_refresh()
  local stale = callback_for(callbacks, 10)
  helpers.response(43, 1)
  test.wait_for_events()
  next_read()
  restore()
  local check = device:get_field(CHECK)
  stale()
  test.wait_for_events()
  assert(device:get_field(CHECK) == check)
  assert(check.reads == 2 and check.pending and check.observations == 1)
  finish_response(43, 2)
  stale()
  helpers.advance(35)
end)

test.register_coroutine_test("Old session callbacks cannot contaminate reinitialization", function()
  helpers.confirm(43)
  local callbacks, restore = capture_delayed_callbacks()
  start_refresh()
  local old_round = callback_for(callbacks, 10)
  local old_total = callback_for(callbacks, 30)
  restore()
  helpers.expect_event(shade.unknown())
  helpers.expect_read()
  confirmation.initialize({}, device)
  test.wait_for_events()
  local check = device:get_field(CHECK)
  old_round()
  old_total()
  test.wait_for_events()
  assert(device:get_field(CHECK) == check and check.reads == 1)
  helpers.confirm(43, 0, 1)
end)

test.register_coroutine_test("A failed read send revokes trust and cancels the verification session",
  function()
    helpers.confirm(43)
    local original = device.send_to_component
    device.send_to_component = function() error("simulated position-read send failure") end
    helpers.expect_event(shade.unknown())
    local ok, err = pcall(confirmation.start, {}, device, "main")
    device.send_to_component = original
    assert(not ok and string.find(err, "simulated position-read send failure", 1, true))
    test.wait_for_events()
    is_unknown()
    assert(device:get_field(CHECK) == nil)
    helpers.advance(35)
  end)

test.register_coroutine_test("A failed motion send must also revoke position trust", function()
  helpers.confirm(43)
  local handler = (require "zemismart").capability_handlers.windowShade.open
  local original = device.send_to_component
  device.send_to_component = function() error("simulated movement-send failure") end
  helpers.expect_event(shade.unknown())
  local ok, err = pcall(handler, {}, device, {
    capability = "windowShade", command = "open", component = "main", args = {},
  })
  device.send_to_component = original
  assert(not ok and string.find(err, "simulated movement-send failure", 1, true))
  test.wait_for_events()
  is_unknown()
end)

test.register_coroutine_test("All non-stop motion commands are read-only while unknown", function()
  for _, request in ipairs({
    { "windowShade", "open" }, { "windowShade", "close" },
    { "windowShadeLevel", "setShadeLevel", { 0 } },
    { "windowShadeLevel", "setShadeLevel", { 100 } },
    { "windowShadePreset", "presetPosition" },
    { "statelessWindowShadeLevelStep", "stepShadeLevel", { 10 } },
    { "statelessWindowShadeLevelStep", "stepShadeLevel", { -10 } },
  }) do
    helpers.command(request[1], request[2], request[3])
  end
  test.wait_for_events()
  is_unknown()
  assert(device:get_field(CHECK).reads == 1)
  helpers.confirm(43)
  helpers.advance(35) -- No queued motion is replayed after recovery.
end)

test.register_coroutine_test("Unknown without an active session starts only a read on movement", function()
  next_read(10)
  next_read(10)
  helpers.advance(10)
  helpers.command("windowShade", "open")
  helpers.expect_read()
  test.wait_for_events()
  is_unknown()
  helpers.confirm(43)
end)

test.register_coroutine_test("Pause may send Stop while unknown and restarts static sampling", function()
  helpers.command("windowShade", "pause")
  expect_motion("Stop")
  test.wait_for_events()
  is_unknown()
  next_read()
  helpers.confirm(43, 1, 2)
end)

test.register_coroutine_test("Pause discards an observation and ignores replies before its next read",
  function()
    helpers.response(43, 1)
    test.wait_for_events()
    helpers.command("windowShade", "pause")
    expect_motion("Stop")
    test.wait_for_events()
    helpers.response(43, 2)
    test.wait_for_events()
    is_unknown()
    assert(device:get_field(CHECK).observations == 0)
    assert(not device:get_field(CHECK).pending)
    next_read()
    helpers.response(43, 3)
    test.wait_for_events()
    is_unknown()
    next_read()
    finish_response(43, 4)
  end)

for _, first_expiry in ipairs({ "read budget", "motion silence" }) do
  test.register_coroutine_test("Repeated commands cannot extend expiry: " .. first_expiry .. " first",
    function()
      helpers.confirm(43)
      local callbacks, restore = capture_delayed_callbacks()
      helpers.command("windowShade", "open")
      expect_motion("UpOrOpen")
      helpers.expect_read()
      test.wait_for_events()
      restore()
      local expiry_callbacks = {}
      for _, entry in ipairs(callbacks) do
        if entry.seconds == 30 then expiry_callbacks[#expiry_callbacks + 1] = entry.callback end
      end
      assert(#expiry_callbacks == 2)
      helpers.advance(9)
      helpers.command("windowShade", "close")
      expect_motion("DownOrClose")
      test.wait_for_events()
      next_read(1)
      helpers.advance(9)
      helpers.command("windowShadeLevel", "setShadeLevel", { 50 })
      expect_motion("GoToLiftPercentage", 50)
      test.wait_for_events()
      next_read(1)
      helpers.advance(9)
      helpers.command("windowShade", "open")
      expect_motion("UpOrOpen")
      test.wait_for_events()
      -- Both deadlines are due together. Exercise each event order explicitly.
      test.mock_time.advance_time(1)
      helpers.expect_event(shade.unknown())
      if first_expiry == "motion silence" then
        helpers.expect_read()
        expiry_callbacks[1]()
      else
        expiry_callbacks[2]()
      end
      test.wait_for_events()
      is_unknown()
      assert(device:get_field(MOTION) == nil)
      local check = device:get_field(CHECK)
      if first_expiry == "motion silence" then
        assert(check and check.mode == "static" and check.reads == 1)
      else
        assert(check == nil)
      end
    end)
end

test.register_coroutine_test("Only strict directional progress renews the motion silence lease", function()
  helpers.confirm(43)
  helpers.command("windowShade", "open")
  expect_motion("UpOrOpen")
  helpers.expect_read()
  test.wait_for_events()
  helpers.advance(9)
  helpers.report(44, 4)
  helpers.expect_event(capabilities.windowShadeLevel.shadeLevel(44))
  helpers.expect_event(shade.opening())
  test.wait_for_events()
  helpers.expect_event(shade.partially_open())
  helpers.advance(29)
  helpers.report(44, 4)
  test.wait_for_events()
  helpers.expect_event(shade.unknown())
  helpers.expect_read()
  helpers.advance(1)
  is_unknown()
  assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == 44)
end)

test.register_coroutine_test("A long movement remains valid while fresh directional progress continues",
  function()
    helpers.confirm(43)
    helpers.command("windowShade", "open")
    expect_motion("UpOrOpen")
    helpers.expect_read()
    test.wait_for_events()
    helpers.advance(9)
    for sequence, level in ipairs({ 44, 45, 46, 47 }) do
      helpers.report(level, sequence)
      helpers.expect_event(capabilities.windowShadeLevel.shadeLevel(level))
      helpers.expect_event(shade.opening())
      test.wait_for_events()
      helpers.expect_event(shade.partially_open())
      helpers.advance(20)
      assert(confirmation.position_is_known(device))
      assert(device:get_field(MOTION) ~= nil)
      assert(device:get_field(CHECK) == nil)
    end
    helpers.report(100, 9)
    helpers.expect_event(shade.unknown())
    helpers.expect_read()
    test.wait_for_events()
    is_unknown()
    assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == 47)
    helpers.confirm(100, 0, 1)
    assert(device:get_field(MOTION) == nil)
    helpers.advance(35)
  end)

test.register_coroutine_test("An old partial-state callback cannot overwrite unknown or restored trust",
  function()
    helpers.confirm(43)
    helpers.command("windowShade", "open")
    expect_motion("UpOrOpen")
    helpers.expect_read()
    test.wait_for_events()
    local callbacks, restore = capture_delayed_callbacks()
    helpers.report(44, 1)
    helpers.expect_event(capabilities.windowShadeLevel.shadeLevel(44))
    helpers.expect_event(shade.opening())
    test.wait_for_events()
    restore()
    local stale_partial = callback_for(callbacks, 2)
    helpers.report(43, 2)
    helpers.expect_event(shade.unknown())
    helpers.expect_read()
    test.wait_for_events()
    stale_partial()
    test.wait_for_events()
    is_unknown()
    helpers.confirm(43, 3, 4)
    stale_partial()
    helpers.advance(35)
    assert(device:get_latest_state("main", "windowShade", "windowShade") == "partially open")
  end)

test.register_coroutine_test("Failed motion during active progress cancels old context without replay",
  function()
    helpers.confirm(43)
    helpers.command("windowShade", "open")
    expect_motion("UpOrOpen")
    helpers.expect_read()
    test.wait_for_events()
    helpers.report(44, 1)
    helpers.expect_event(capabilities.windowShadeLevel.shadeLevel(44))
    helpers.expect_event(shade.opening())
    test.wait_for_events()
    local handler = (require "zemismart").capability_handlers.windowShade.close
    local original = device.send_to_component
    device.send_to_component = function() error("simulated active-motion send failure") end
    helpers.expect_event(shade.unknown())
    local ok, err = pcall(handler, {}, device, {
      capability = "windowShade", command = "close", component = "main", args = {},
    })
    device.send_to_component = original
    assert(not ok and string.find(err, "simulated active-motion send failure", 1, true))
    test.wait_for_events()
    is_unknown()
    assert(device:get_field(CHECK) == nil and device:get_field(MOTION) == nil)
    assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == 44)
    helpers.advance(35)
  end)

test.register_coroutine_test("Reinitialization cannot derive trust from an earlier cached position", function()
  helpers.confirm(43)
  test.socket.device_lifecycle:__queue_receive({ device.id, "init" })
  helpers.expect_event(shade.unknown())
  helpers.expect_read()
  test.wait_for_events()
  is_unknown()
  assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == 43)
  helpers.report(43, 0)
  test.wait_for_events()
  is_unknown()
  helpers.confirm(43, 0, 1)
end)

test.register_coroutine_test("A target report requires static reads before emitting the endpoint", function()
  helpers.confirm(43)
  helpers.command("windowShade", "open")
  expect_motion("UpOrOpen")
  helpers.expect_read()
  test.wait_for_events()
  helpers.report(100, 9)
  helpers.expect_event(shade.unknown())
  helpers.expect_read()
  test.wait_for_events()
  is_unknown()
  assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == 43)
  helpers.confirm(100, 0, 1)
end)

test.register_coroutine_test("A direction-conflicting report is quarantined without false movement", function()
  helpers.confirm(43)
  helpers.command("windowShade", "open")
  expect_motion("UpOrOpen")
  helpers.expect_read()
  test.wait_for_events()
  helpers.report(42, 8)
  helpers.expect_event(shade.unknown())
  helpers.expect_read()
  test.wait_for_events()
  is_unknown()
  assert(device:get_latest_state("main", "windowShadeLevel", "shadeLevel") == 43)
end)

test.register_coroutine_test("Removal invalidates round total motion partial and step callbacks", function()
  helpers.confirm(43)
  local callbacks, restore = capture_delayed_callbacks()
  helpers.command("windowShade", "open")
  expect_motion("UpOrOpen")
  helpers.expect_read()
  test.wait_for_events()
  helpers.report(44, 1)
  helpers.expect_event(capabilities.windowShadeLevel.shadeLevel(44))
  helpers.expect_event(shade.opening())
  test.wait_for_events()
  helpers.command("statelessWindowShadeLevelStep", "stepShadeLevel", { 10 })
  expect_motion("GoToLiftPercentage", 54)
  helpers.expect_read()
  test.wait_for_events()
  restore()
  local scheduled = {}
  for _, entry in ipairs(callbacks) do scheduled[entry.seconds] = true end
  assert(scheduled[2] and scheduled[10] and scheduled[15] and scheduled[30])
  -- Let the real lifecycle dispatcher perform cleanup with all contexts active.
  test.socket.device_lifecycle:__queue_receive({ device.id, "removed" })
  test.wait_for_events()
  -- SDK deletion invalidates methods, but a timer event can already be queued.
  -- Only closure-local cancellation tokens may be consulted before the device.
  for _, entry in ipairs(callbacks) do
    local ok, err = pcall(entry.callback)
    assert(ok, "callback touched a deleted device: " .. tostring(err))
  end
  helpers.advance(60) -- Do not access the device after SDK invalidates it.
end)

test.register_coroutine_test("Already-complete step timer cancellation still invalidates saved fields",
  function()
    helpers.confirm(43)
    local callbacks, restore_capture = capture_delayed_callbacks()
    helpers.command("statelessWindowShadeLevelStep", "stepShadeLevel", { 10 })
    expect_motion("GoToLiftPercentage", 53)
    helpers.expect_read()
    test.wait_for_events()
    restore_capture()
    local stale = callback_for(callbacks, 15)
    local old_timer = device:get_field("_targetLevelTimeOut")
    local old_generation = device:get_field("_targetLevelGeneration")
    local original_cancel = device.thread.cancel_timer
    device.thread.cancel_timer = function(thread, timer)
      if timer == old_timer then error("simulated already-complete step timer") end
      return original_cancel(thread, timer)
    end
    local ok, err = pcall(shade_utils.clear_step_target, device)
    device.thread.cancel_timer = original_cancel
    assert(ok, tostring(err))
    assert(device:get_field("_latestTargetLevel") == nil)
    assert(device:get_field("_targetLevelTimeOut") == nil)
    assert(device:get_field("_targetLevelGeneration") == nil)
    assert(old_generation.active == false)
    stale()
    test.wait_for_events()
  end)

test.register_coroutine_test("Replacing a completed step timer cannot let its old callback clear the new target",
  function()
    helpers.confirm(43)
    local callbacks, restore_capture = capture_delayed_callbacks()
    helpers.command("statelessWindowShadeLevelStep", "stepShadeLevel", { 10 })
    expect_motion("GoToLiftPercentage", 53)
    helpers.expect_read()
    test.wait_for_events()
    restore_capture()
    local stale = callback_for(callbacks, 15)
    local old_timer = device:get_field("_targetLevelTimeOut")
    local old_generation = device:get_field("_targetLevelGeneration")
    local original_cancel = device.thread.cancel_timer
    device.thread.cancel_timer = function(thread, timer)
      if timer == old_timer then error("simulated already-complete step timer") end
      return original_cancel(thread, timer)
    end
    helpers.command("statelessWindowShadeLevelStep", "stepShadeLevel", { 1 })
    expect_motion("GoToLiftPercentage", 54)
    test.wait_for_events()
    device.thread.cancel_timer = original_cancel
    assert(old_generation.active == false)
    local new_timer = device:get_field("_targetLevelTimeOut")
    assert(new_timer ~= nil and new_timer ~= old_timer)
    stale()
    test.wait_for_events()
    assert(device:get_field("_latestTargetLevel") == 54)
    assert(device:get_field("_targetLevelTimeOut") == new_timer)
    assert(device:get_field("_targetLevelGeneration").active)
  end)

test.register_coroutine_test("Battery profile retains its original initialization without trust reads",
  function()
    assert(battery_device:get_field(CHECK) == nil)
    assert(battery_device:get_latest_state("main", "windowShade", "windowShade") == nil)
  end, { test_init = function() helpers.initialize_device(battery_device) end })

test.run_registered_tests()
