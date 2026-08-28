-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Test for statelessWindowShadeLevelStep capability with Level cluster devices
-- Tests devices like AXIS Gear that use Level cluster for window covering control

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local Level = clusters.Level
local WindowCovering = clusters.WindowCovering

-- Create mock AXIS Gear device using Level cluster
-- This device matches the axis sub-driver which uses Level cluster
local axis_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("window-treatment-profile.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "AXIS",
        model = "Gear",
        server_clusters = { Level.ID, WindowCovering.ID }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(axis_device)
  test.socket.capability:__expect_send(
    axis_device:generate_test_message("main", capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, {visibility = {displayed=false}}))
  )
  test.socket.capability:__expect_send(
    axis_device:generate_test_message("main", capabilities.windowShadePreset.position(50, {visibility = {displayed=false}}))
  )
end

test.set_test_init_function(test_init)

-- Test 1: Boundary condition - stepSize = 0 should not send command
test.register_coroutine_test(
  "statelessWindowShadeLevelStep with Level cluster - stepSize 0 does not send command",
  function()
    -- Set initial state via Level cluster report: 50% (127 out of 254)
    test.socket.zigbee:__queue_receive({
      axis_device.id,
      Level.attributes.CurrentLevel:build_test_attr_report(axis_device, 127)
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 50 } }
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value
    axis_device:set_field("_latestTargetLevel", 50)

    -- Send stepShadeLevel command with stepSize = 0
    test.socket.capability:__queue_receive({
      axis_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 0 } }
    })

    -- Should NOT send any Zigbee command (stepSize 0 is ignored)
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

-- Test 2: Normal step up operation with Level cluster
test.register_coroutine_test(
  "statelessWindowShadeLevelStep with Level cluster - normal step up",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    -- Set initial state: Level cluster reports 50% (127 out of 254)
    test.socket.zigbee:__queue_receive({
      axis_device.id,
      Level.attributes.CurrentLevel:build_test_attr_report(axis_device, 127)
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 50 } }
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value
    axis_device:set_field("_latestTargetLevel", 50)

    -- Send stepShadeLevel command with stepSize = 10
    -- new_target_level = clamp(50 + 10, 0, 100) = 60
    test.socket.capability:__queue_receive({
      axis_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 } }
    })

    -- AXIS sub-driver emits shadeLevel event when handling setShadeLevel (injected by main driver)
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 60 } }
    })
    -- AXIS sub-driver also emits windowShade event (opening because 60 > 50)
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "opening" } }
    })

    -- Should send MoveToLevelWithOnOff with level 60 (152 out of 254, rounded from 152.4)
    test.socket.zigbee:__expect_send({
      axis_device.id,
      Level.server.commands.MoveToLevelWithOnOff(axis_device, 152)
    })
  end,
  { min_api_version = 17 }
)

-- Test 3: Normal step down operation with Level cluster
test.register_coroutine_test(
  "statelessWindowShadeLevelStep with Level cluster - normal step down",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    -- Set initial state: Level cluster reports 75% (191 out of 254)
    test.socket.zigbee:__queue_receive({
      axis_device.id,
      Level.attributes.CurrentLevel:build_test_attr_report(axis_device, 191)
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 75 } }
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value
    axis_device:set_field("_latestTargetLevel", 75)

    -- Send stepShadeLevel command with stepSize = -25
    -- new_target_level = clamp(75 + (-25), 0, 100) = 50
    test.socket.capability:__queue_receive({
      axis_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -25 } }
    })

    -- AXIS sub-driver emits shadeLevel event when handling setShadeLevel (injected by main driver)
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 50 } }
    })
    -- AXIS sub-driver also emits windowShade event (closing because 50 < 75)
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "closing" } }
    })

    -- Should send MoveToLevelWithOnOff with level 50 (127 out of 254)
    test.socket.zigbee:__expect_send({
      axis_device.id,
      Level.server.commands.MoveToLevelWithOnOff(axis_device, 127)
    })
  end,
  { min_api_version = 17 }
)

-- Test 4: Boundary condition - value clamped to 100 (maximum)
test.register_coroutine_test(
  "statelessWindowShadeLevelStep with Level cluster - value clamped to 100",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    -- Set initial state: Level cluster reports 90% (229 out of 254)
    test.socket.zigbee:__queue_receive({
      axis_device.id,
      Level.attributes.CurrentLevel:build_test_attr_report(axis_device, 229)
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 90 } }
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value
    axis_device:set_field("_latestTargetLevel", 90)

    -- Send stepShadeLevel command with stepSize = 50
    -- new_target_level = clamp(90 + 50, 0, 100) = 100
    test.socket.capability:__queue_receive({
      axis_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 50 } }
    })

    -- AXIS sub-driver emits shadeLevel event when handling setShadeLevel (injected by main driver)
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 100 } }
    })
    -- AXIS sub-driver also emits windowShade event (opening because 100 > 90)
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "opening" } }
    })

    -- Should send MoveToLevelWithOnOff with level 100 (254 out of 254)
    test.socket.zigbee:__expect_send({
      axis_device.id,
      Level.server.commands.MoveToLevelWithOnOff(axis_device, 254)
    })
  end,
  { min_api_version = 17 }
)

-- Test 5: Boundary condition - value clamped to 0 (minimum)
test.register_coroutine_test(
  "statelessWindowShadeLevelStep with Level cluster - value clamped to 0",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    -- Set initial state: Level cluster reports 20% (51 out of 254)
    test.socket.zigbee:__queue_receive({
      axis_device.id,
      Level.attributes.CurrentLevel:build_test_attr_report(axis_device, 51)
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 20 } }
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value
    axis_device:set_field("_latestTargetLevel", 20)

    -- Send stepShadeLevel command with stepSize = -50
    -- new_target_level = clamp(20 + (-50), 0, 100) = 0
    test.socket.capability:__queue_receive({
      axis_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -50 } }
    })

    -- AXIS sub-driver emits shadeLevel event when handling setShadeLevel (injected by main driver)
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 0 } }
    })
    -- AXIS sub-driver also emits windowShade event (closing because 0 < 20)
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "closing" } }
    })

    -- Should send MoveToLevelWithOnOff with level 0 (0 out of 254)
    test.socket.zigbee:__expect_send({
      axis_device.id,
      Level.server.commands.MoveToLevelWithOnOff(axis_device, 0)
    })
  end,
  { min_api_version = 17 }
)

-- Test 6: Continuous step operations with mixed directions
test.register_coroutine_test(
  "statelessWindowShadeLevelStep with Level cluster - continuous steps with mixed directions",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    -- Set initial state: Level cluster reports 50% (127 out of 254)
    test.socket.zigbee:__queue_receive({
      axis_device.id,
      Level.attributes.CurrentLevel:build_test_attr_report(axis_device, 127)
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 50 } }
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value
    axis_device:set_field("_latestTargetLevel", 50)

    -- Step 1: stepSize = 10 (up) -> 60%
    test.socket.capability:__queue_receive({
      axis_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 } }
    })
    -- AXIS sub-driver emits shadeLevel and windowShade events
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 60 } }
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "opening" } }
    })
    test.socket.zigbee:__expect_send({
      axis_device.id,
      Level.server.commands.MoveToLevelWithOnOff(axis_device, 152)
    })
    test.wait_for_events()

    -- Step 2: stepSize = -5 (down) -> 55%
    test.socket.capability:__queue_receive({
      axis_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -5 } }
    })
    -- AXIS sub-driver emits shadeLevel and windowShade events
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 55 } }
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "closing" } }
    })
    test.socket.zigbee:__expect_send({
      axis_device.id,
      Level.server.commands.MoveToLevelWithOnOff(axis_device, 140)
    })
    test.wait_for_events()

    -- Step 3: stepSize = 20 (up) -> 75%
    test.socket.capability:__queue_receive({
      axis_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 20 } }
    })
    -- AXIS sub-driver emits shadeLevel and windowShade events
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 75 } }
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "opening" } }
    })
    test.socket.zigbee:__expect_send({
      axis_device.id,
      Level.server.commands.MoveToLevelWithOnOff(axis_device, 191)
    })
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

-- Test 7: nil stepSize should not send command
test.register_coroutine_test(
  "statelessWindowShadeLevelStep with Level cluster - nil stepSize does not send command",
  function()
    -- Set initial state: Level cluster reports 50% (127 out of 254)
    test.socket.zigbee:__queue_receive({
      axis_device.id,
      Level.attributes.CurrentLevel:build_test_attr_report(axis_device, 127)
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 50 } }
    })
    test.socket.capability:__expect_send({
      axis_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value
    axis_device:set_field("_latestTargetLevel", 50)

    -- Send stepShadeLevel command with nil stepSize
    test.socket.capability:__queue_receive({
      axis_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = {} }
    })

    -- Should NOT send any Zigbee command
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

test.run_registered_tests()
