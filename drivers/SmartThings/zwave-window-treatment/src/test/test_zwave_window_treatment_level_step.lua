-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Tests for statelessWindowShadeLevelStep on Z-Wave window treatments using the
-- default SwitchMultilevel handling (no subdriver match)

local capabilities = require "st.capabilities"
local constants = require "st.zwave.constants"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=4 })

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("window-treatment-power.yml"),
  zwave_endpoints = {
    {
      command_classes = {
        {value = zw.SWITCH_MULTILEVEL}
      }
    }
  }
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, {visibility = {displayed=false}}))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.windowShadePreset.position(50, {visibility = {displayed=false}}))
  )
end
test.set_test_init_function(test_init)

local function report_level(level)
  return {
    mock_device.id,
    zw_test_utils.zwave_test_build_receive_command(SwitchMultilevel:Report({
      target_value = level,
      current_value = level,
      duration = 0
    }))
  }
end

-- Expects the windowShade and windowShadeLevel state emitted for a reported level
local function expect_reported_level(level)
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(level))
  )
end

-- Expects the Set sent for a given level on the default path
local function expect_set(level)
  test.socket.zwave:__expect_send(
    zw_test_utils.zwave_test_build_send_command(
      mock_device,
      SwitchMultilevel:Set({
        value = level,
        duration = constants.DEFAULT_DIMMING_DURATION
      })
    )
  )
end

local function queue_step(step)
  test.socket.capability:__queue_receive({
    mock_device.id,
    { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { step } }
  })
end

test.register_coroutine_test(
  "stepShadeLevel with stepSize 0 should not send a command",
  function()
    test.socket.zwave:__queue_receive(report_level(50))
    expect_reported_level(50)
    test.wait_for_events()

    queue_step(0)
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

test.register_coroutine_test(
  "stepShadeLevel should step up from the reported level",
  function()
    test.socket.zwave:__queue_receive(report_level(50))
    expect_reported_level(50)
    test.wait_for_events()

    queue_step(10)
    expect_set(60)
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

test.register_coroutine_test(
  "stepShadeLevel should step down from the reported level",
  function()
    test.socket.zwave:__queue_receive(report_level(50))
    expect_reported_level(50)
    test.wait_for_events()

    queue_step(-25)
    expect_set(25)
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

test.register_coroutine_test(
  "stepShadeLevel should accumulate steps within the timeout window",
  function()
    test.socket.zwave:__queue_receive(report_level(50))
    expect_reported_level(50)
    test.wait_for_events()

    queue_step(10)
    expect_set(60)
    test.wait_for_events()

    test.mock_time.advance_time(5)
    queue_step(10)
    expect_set(70)
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

test.register_coroutine_test(
  "stepShadeLevel should clamp the target to 0-100",
  function()
    test.socket.zwave:__queue_receive(report_level(95))
    expect_reported_level(95)
    test.wait_for_events()

    queue_step(50)
    -- Target clamps to 100, which the default handler sends as 99
    expect_set(99)
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

test.register_coroutine_test(
  "stepShadeLevel should start from the reported level again after the timeout",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(121, "oneshot")
    test.socket.zwave:__queue_receive(report_level(50))
    expect_reported_level(50)
    test.wait_for_events()

    queue_step(10)
    expect_set(60)
    test.wait_for_events()

    -- Timeout is 120 seconds; the accumulated target is cleared after it elapses
    test.mock_time.advance_time(121)
    test.wait_for_events()

    queue_step(10)
    expect_set(60)
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

test.register_coroutine_test(
  "stepShadeLevel should keep accumulating just before the 120 second timeout",
  function()
    test.socket.zwave:__queue_receive(report_level(50))
    expect_reported_level(50)
    test.wait_for_events()

    queue_step(10)
    expect_set(60)
    test.wait_for_events()

    test.timer.__create_and_queue_test_time_advance_timer(119, "oneshot")
    test.wait_for_events()

    queue_step(10)
    expect_set(70)
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

test.run_registered_tests()
