-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Test for statelessWindowShadeLevelStep capability with Somfy (reverse) devices
-- Tests devices like Somfy Glydea that use inverted lift percentage

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local WindowCovering = clusters.WindowCovering

-- Create mock Somfy Glydea device using WindowCovering cluster with inverted logic
-- This device matches the somfy sub-driver which inverts the lift percentage
local somfy_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("window-treatment-profile.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "SOMFY",
        model = "Glydea Ultra Curtain",
        server_clusters = { WindowCovering.ID }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(somfy_device)
  test.socket.capability:__expect_send(
    somfy_device:generate_test_message("main", capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, {visibility = {displayed=false}}))
  )
  test.socket.capability:__expect_send(
    somfy_device:generate_test_message("main", capabilities.windowShadePreset.position(50, {visibility = {displayed=false}}))
  )
end

test.set_test_init_function(test_init)

-- Test 1: Boundary condition - stepSize = 0 should not send command
test.register_coroutine_test(
  "statelessWindowShadeLevelStep with Somfy (reverse) - stepSize 0 does not send command",
  function()
    -- Set initial state via WindowCovering cluster report: 50% (inverted: device reports 50 for 50% shade)
    test.socket.zigbee:__queue_receive({
      somfy_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(somfy_device, 50)
    })
    test.socket.capability:__expect_send({
      somfy_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 50 } }
    })
    -- Somfy sub-driver emits "opening" for initial report when no previous state exists
    test.socket.capability:__expect_send({
      somfy_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "opening" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value
    somfy_device:set_field("_latestTargetLevel", 50)

    -- Send stepShadeLevel command with stepSize = 0
    test.socket.capability:__queue_receive({
      somfy_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 0 } }
    })

    -- Should NOT send any Zigbee command (stepSize 0 is ignored)
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

-- Test 2: Normal step up operation with Somfy (reverse) device
-- Somfy inverts the value: shadeLevel 60 means device goes to 100-60=40
test.register_coroutine_test(
  "statelessWindowShadeLevelStep with Somfy (reverse) - normal step up",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    -- Set initial state: WindowCovering cluster reports 50 (inverted: 100-50=50 shade level)
    test.socket.zigbee:__queue_receive({
      somfy_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(somfy_device, 50)
    })
    test.socket.capability:__expect_send({
      somfy_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 50 } }
    })
    -- Somfy sub-driver emits "opening" for initial report when no previous state exists
    test.socket.capability:__expect_send({
      somfy_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "opening" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value
    somfy_device:set_field("_latestTargetLevel", 50)

    -- Send stepShadeLevel command with stepSize = 10
    -- new_target_level = clamp(50 + 10, 0, 100) = 60
    test.socket.capability:__queue_receive({
      somfy_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 } }
    })

    -- Note: Somfy sub-driver's window_shade_level_cmd directly sends Zigbee command without emitting events
    -- Somfy sub-driver's window_shade_level_cmd inverts the value: 100 - 60 = 40
    test.socket.zigbee:__expect_send({
      somfy_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(somfy_device, 40)
    })
  end,
  { min_api_version = 17 }
)

-- Test 3: Normal step down operation with Somfy (reverse) device
test.register_coroutine_test(
  "statelessWindowShadeLevelStep with Somfy (reverse) - normal step down",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    -- Set initial state: WindowCovering cluster reports 25 (inverted: 100-25=75 shade level)
    test.socket.zigbee:__queue_receive({
      somfy_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(somfy_device, 25)
    })
    test.socket.capability:__expect_send({
      somfy_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 75 } }
    })
    -- Somfy sub-driver emits "opening" for initial report when no previous state exists
    test.socket.capability:__expect_send({
      somfy_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "opening" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value
    somfy_device:set_field("_latestTargetLevel", 75)

    -- Send stepShadeLevel command with stepSize = -25
    -- new_target_level = clamp(75 + (-25), 0, 100) = 50
    test.socket.capability:__queue_receive({
      somfy_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -25 } }
    })

    -- Note: Somfy sub-driver's window_shade_level_cmd directly sends Zigbee command without emitting events
    -- Somfy sub-driver's window_shade_level_cmd inverts the value: 100 - 50 = 50
    test.socket.zigbee:__expect_send({
      somfy_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(somfy_device, 50)
    })
  end,
  { min_api_version = 17 }
)

-- Test 4: Boundary condition - value clamped to 100 (maximum)
test.register_coroutine_test(
  "statelessWindowShadeLevelStep with Somfy (reverse) - value clamped to 100",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    -- Set initial state: WindowCovering cluster reports 10 (inverted: 100-10=90 shade level)
    test.socket.zigbee:__queue_receive({
      somfy_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(somfy_device, 10)
    })
    test.socket.capability:__expect_send({
      somfy_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 90 } }
    })
    -- Somfy sub-driver emits "opening" for initial report when no previous state exists
    test.socket.capability:__expect_send({
      somfy_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "opening" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value
    somfy_device:set_field("_latestTargetLevel", 90)

    -- Send stepShadeLevel command with stepSize = 50
    -- new_target_level = clamp(90 + 50, 0, 100) = 100
    test.socket.capability:__queue_receive({
      somfy_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 50 } }
    })

    -- Note: Somfy sub-driver's window_shade_level_cmd directly sends Zigbee command without emitting events
    -- Somfy sub-driver's window_shade_level_cmd inverts the value: 100 - 100 = 0
    test.socket.zigbee:__expect_send({
      somfy_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(somfy_device, 0)
    })
  end,
  { min_api_version = 17 }
)

-- Test 5: Boundary condition - value clamped to 0 (minimum)
test.register_coroutine_test(
  "statelessWindowShadeLevelStep with Somfy (reverse) - value clamped to 0",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    -- Set initial state: WindowCovering cluster reports 80 (inverted: 100-80=20 shade level)
    test.socket.zigbee:__queue_receive({
      somfy_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(somfy_device, 80)
    })
    test.socket.capability:__expect_send({
      somfy_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 20 } }
    })
    -- Somfy sub-driver emits "opening" for initial report when no previous state exists
    test.socket.capability:__expect_send({
      somfy_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "opening" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value
    somfy_device:set_field("_latestTargetLevel", 20)

    -- Send stepShadeLevel command with stepSize = -50
    -- new_target_level = clamp(20 + (-50), 0, 100) = 0
    test.socket.capability:__queue_receive({
      somfy_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -50 } }
    })

    -- Note: Somfy sub-driver's window_shade_level_cmd directly sends Zigbee command without emitting events
    -- Somfy sub-driver's window_shade_level_cmd inverts the value: 100 - 0 = 100
    test.socket.zigbee:__expect_send({
      somfy_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(somfy_device, 100)
    })
  end,
  { min_api_version = 17 }
)

-- Test 6: Continuous step operations with mixed directions
test.register_coroutine_test(
  "statelessWindowShadeLevelStep with Somfy (reverse) - continuous steps with mixed directions",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    -- Set initial state: WindowCovering cluster reports 50 (inverted: 100-50=50 shade level)
    test.socket.zigbee:__queue_receive({
      somfy_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(somfy_device, 50)
    })
    test.socket.capability:__expect_send({
      somfy_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 50 } }
    })
    -- Somfy sub-driver emits "opening" for initial report when no previous state exists
    test.socket.capability:__expect_send({
      somfy_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "opening" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value
    somfy_device:set_field("_latestTargetLevel", 50)

    -- Step 1: stepSize = 10 (up) -> 60%
    test.socket.capability:__queue_receive({
      somfy_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 } }
    })
    -- Note: Somfy sub-driver's window_shade_level_cmd directly sends Zigbee command without emitting events
    -- Somfy sub-driver's window_shade_level_cmd inverts the value: 100 - 60 = 40
    test.socket.zigbee:__expect_send({
      somfy_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(somfy_device, 40)
    })
    test.wait_for_events()

    -- Step 2: stepSize = -5 (down) -> 55%
    test.socket.capability:__queue_receive({
      somfy_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -5 } }
    })
    -- Note: Somfy sub-driver's window_shade_level_cmd directly sends Zigbee command without emitting events
    -- Somfy sub-driver's window_shade_level_cmd inverts the value: 100 - 55 = 45
    test.socket.zigbee:__expect_send({
      somfy_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(somfy_device, 45)
    })
    test.wait_for_events()

    -- Step 3: stepSize = 20 (up) -> 75%
    test.socket.capability:__queue_receive({
      somfy_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 20 } }
    })
    -- Note: Somfy sub-driver's window_shade_level_cmd directly sends Zigbee command without emitting events
    -- Somfy sub-driver's window_shade_level_cmd inverts the value: 100 - 75 = 25
    test.socket.zigbee:__expect_send({
      somfy_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(somfy_device, 25)
    })
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

-- Test 7: nil stepSize should not send command
test.register_coroutine_test(
  "statelessWindowShadeLevelStep with Somfy (reverse) - nil stepSize does not send command",
  function()
    -- Set initial state: WindowCovering cluster reports 50 (inverted: 100-50=50 shade level)
    test.socket.zigbee:__queue_receive({
      somfy_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(somfy_device, 50)
    })
    test.socket.capability:__expect_send({
      somfy_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 50 } }
    })
    -- Somfy sub-driver emits "opening" for initial report when no previous state exists
    test.socket.capability:__expect_send({
      somfy_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "opening" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value
    somfy_device:set_field("_latestTargetLevel", 50)

    -- Send stepShadeLevel command with nil stepSize
    test.socket.capability:__queue_receive({
      somfy_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = {} }
    })

    -- Should NOT send any Zigbee command
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

test.run_registered_tests()
