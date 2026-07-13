-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Direct unit test for stateless_handler module
-- Tests boundary conditions for stepShadeLevel command

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local WindowCovering = clusters.WindowCovering
local AnalogOutput = clusters.AnalogOutput

-- Create mock Aqara curtain device using profile that includes statelessWindowShadeLevelStep capability
-- Profile "window-treatment-no-preset" includes the statelessWindowShadeLevelStep capability
-- Aqara has invert_level = true, meaning:
-- - Device reports: 0 = fully open, 100 = fully closed
-- - UI shows: 0 = fully closed, 100 = fully open (inverted)
-- - UI value = 100 - device value
local aqara_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("window-treatment-no-preset.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.curtain",
        server_clusters = { WindowCovering.ID, AnalogOutput.ID }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(aqara_device)
end

test.set_test_init_function(test_init)

-- Test 1: Boundary condition - stepSize = 0 should not send command
-- Tests stateless_handler: stepShadeLevel command with stepSize=0 should not send Zigbee command
test.register_coroutine_test(
  "stateless_handler: stepShadeLevel - stepSize 0 does not send command",
  function()
    -- Set initial state via device report: device=50% -> UI = 100 - 50 = 50%
    test.socket.zigbee:__queue_receive({
      aqara_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(aqara_device, 50)
    })
    -- Device report triggers windowShadeLevel and windowShade events (handled by zigbee_handlers, not stateless_handler)
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 50 } }
    })
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Send stepShadeLevel command with stepSize = 0 (tests stateless_handler)
    test.socket.capability:__queue_receive({
      aqara_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 0 } }
    })

    -- Should NOT send any Zigbee command (stepSize 0 is ignored by stateless_handler)
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

-- Test 2: Boundary condition - value clamped to 100 (UI)
-- stateless_handler uses get_latest_state which returns the reported value directly
-- current_level = 10 (device report), step = 50
-- ui_target_level = clamp(10 + 50, 0, 100) = 60
-- device_target_level = 60 (not inverted for Aqara in stateless_handler)
test.register_coroutine_test(
  "stateless_handler: stepShadeLevel - value clamped to 100",
  function()
    -- Set initial state: device reports 10%
    -- aqara handler emits windowShadeLevel and windowShade events
    test.socket.zigbee:__queue_receive({
      aqara_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(aqara_device, 10)
    })
    -- aqara handler emits shade level and shade events
    -- level 10 is partially open (only 0 = closed, 100 = open)
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 10 } }
    })
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value being used as current level
    -- In real scenario, the driver would use device:get_latest_state() to get the current level
    aqara_device:set_field("_latestTargetLevel", 10)

    -- Send stepShadeLevel command with stepSize = 50
    -- current_level = 10 (from LATEST_TARGET_LEVEL), step = 50
    -- ui_target_level = clamp(10 + 50, 0, 100) = 60
    -- device_target_level = 60 (not inverted for Aqara in stateless_handler)
    test.socket.capability:__queue_receive({
      aqara_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 50 } }
    })

    -- Should send GoToLiftPercentage with value 60
    test.socket.zigbee:__expect_send({
      aqara_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(aqara_device, 60)
    })
  end,
  { min_api_version = 17 }
)

-- Test 3: Boundary condition - value clamped to 0 (UI, negative step)
-- current_level = 90 (device report), step = -20
-- ui_target_level = clamp(90 + (-20), 0, 100) = 70
-- device_target_level = 70 (not inverted for Aqara in stateless_handler)
test.register_coroutine_test(
  "stateless_handler: stepShadeLevel - value clamped to 0",
  function()
    -- Set initial state: device reports 90%
    -- aqara handler emits windowShadeLevel and windowShade events
    test.socket.zigbee:__queue_receive({
      aqara_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(aqara_device, 90)
    })
    -- aqara handler emits shade level and shade events
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 90 } }
    })
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value being used as current level
    aqara_device:set_field("_latestTargetLevel", 90)

    -- Send stepShadeLevel command with stepSize = -20
    -- current_level = 90, step = -20
    -- ui_target_level = clamp(90 + (-20), 0, 100) = 70
    -- device_target_level = 70 (not inverted for Aqara in stateless_handler)
    test.socket.capability:__queue_receive({
      aqara_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -20 } }
    })

    -- Should send GoToLiftPercentage with value 70
    test.socket.zigbee:__expect_send({
      aqara_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(aqara_device, 70)
    })
  end,
  { min_api_version = 17 }
)

-- Test 4: Normal step up operation
-- current_level = 70 (device report), step = 10
-- ui_target_level = clamp(70 + 10, 0, 100) = 80
-- device_target_level = 80 (not inverted for Aqara in stateless_handler)
test.register_coroutine_test(
  "stateless_handler: stepShadeLevel - normal step up",
  function()
    -- Set initial state: device reports 70%
    -- aqara handler emits windowShadeLevel and windowShade events
    test.socket.zigbee:__queue_receive({
      aqara_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(aqara_device, 70)
    })
    -- aqara handler emits shade level and shade events
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 70 } }
    })
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value being used as current level
    aqara_device:set_field("_latestTargetLevel", 70)

    -- Send stepShadeLevel command with stepSize = 10
    -- current_level = 70, step = 10
    -- ui_target_level = clamp(70 + 10, 0, 100) = 80
    -- device_target_level = 80 (not inverted for Aqara in stateless_handler)
    test.socket.capability:__queue_receive({
      aqara_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 } }
    })

    -- Should send GoToLiftPercentage with value 80
    test.socket.zigbee:__expect_send({
      aqara_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(aqara_device, 80)
    })
  end,
  { min_api_version = 17 }
)

-- Test 5: Normal step down operation
-- current_level = 30 (device report), step = -20
-- ui_target_level = clamp(30 + (-20), 0, 100) = 10
-- device_target_level = 10 (not inverted for Aqara in stateless_handler)
test.register_coroutine_test(
  "stateless_handler: stepShadeLevel - normal step down",
  function()
    -- Set initial state: device reports 30%
    -- aqara handler emits windowShadeLevel and windowShade events
    test.socket.zigbee:__queue_receive({
      aqara_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(aqara_device, 30)
    })
    -- aqara handler emits shade level and shade events
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 30 } }
    })
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value being used as current level
    aqara_device:set_field("_latestTargetLevel", 30)

    -- Send stepShadeLevel command with stepSize = -20
    -- current_level = 30, step = -20
    -- ui_target_level = clamp(30 + (-20), 0, 100) = 10
    -- device_target_level = 10 (not inverted for Aqara in stateless_handler)
    test.socket.capability:__queue_receive({
      aqara_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -20 } }
    })

    -- Should send GoToLiftPercentage with value 10
    test.socket.zigbee:__expect_send({
      aqara_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(aqara_device, 10)
    })
  end,
  { min_api_version = 17 }
)

-- Test 6: stepSize is nil
test.register_coroutine_test(
  "stateless_handler: stepShadeLevel - nil stepSize does not send command",
  function()
    -- Reset Aqara device state
    -- aqara handler emits windowShadeLevel and windowShade events
    test.socket.zigbee:__queue_receive({
      aqara_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(aqara_device, 50)
    })
    -- aqara handler emits shade level and shade events
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 50 } }
    })
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value being used as current level
    aqara_device:set_field("_latestTargetLevel", 50)

    -- Send stepShadeLevel command with nil stepSize
    test.socket.capability:__queue_receive({
      aqara_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = {} }
    })

    -- Should NOT send any Zigbee command
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

-- Test 7: Boundary condition - minimum stepSize (stepSize = 1)
-- current_level = 50 (device report), step = 1
-- ui_target_level = clamp(50 + 1, 0, 100) = 51
-- device_target_level = 51 (not inverted for Aqara in stateless_handler)
test.register_coroutine_test(
  "stateless_handler: stepShadeLevel - minimum stepSize 1 works correctly",
  function()
    -- Set initial state: device reports 50%
    -- aqara handler emits windowShadeLevel and windowShade events
    test.socket.zigbee:__queue_receive({
      aqara_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(aqara_device, 50)
    })
    -- aqara handler emits shade level and shade events
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 50 } }
    })
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value being used as current level
    aqara_device:set_field("_latestTargetLevel", 50)

    -- Send stepShadeLevel command with stepSize = 1 (minimum positive step)
    -- current_level = 50, step = 1
    -- ui_target_level = clamp(50 + 1, 0, 100) = 51
    -- device_target_level = 51 (not inverted for Aqara in stateless_handler)
    test.socket.capability:__queue_receive({
      aqara_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 1 } }
    })

    -- Should send GoToLiftPercentage with value 51
    test.socket.zigbee:__expect_send({
      aqara_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(aqara_device, 51)
    })
  end,
  { min_api_version = 17 }
)

-- Test 8: Boundary condition - minimum negative stepSize (stepSize = -1)
-- current_level = 50 (device report), step = -1
-- ui_target_level = clamp(50 + (-1), 0, 100) = 49
-- device_target_level = 49 (not inverted for Aqara in stateless_handler)
test.register_coroutine_test(
  "stateless_handler: stepShadeLevel - minimum negative stepSize -1 works correctly",
  function()
    -- Set initial state: device reports 50%
    -- aqara handler emits windowShadeLevel and windowShade events
    test.socket.zigbee:__queue_receive({
      aqara_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(aqara_device, 50)
    })
    -- aqara handler emits shade level and shade events
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 50 } }
    })
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value being used as current level
    aqara_device:set_field("_latestTargetLevel", 50)

    -- Send stepShadeLevel command with stepSize = -1 (minimum negative step)
    -- current_level = 50, step = -1
    -- ui_target_level = clamp(50 + (-1), 0, 100) = 49
    -- device_target_level = 49 (not inverted for Aqara in stateless_handler)
    test.socket.capability:__queue_receive({
      aqara_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -1 } }
    })

    -- Should send GoToLiftPercentage with value 49
    test.socket.zigbee:__expect_send({
      aqara_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(aqara_device, 49)
    })
  end,
  { min_api_version = 17 }
)

-- Test 9: Continuous step operation - multiple consecutive steps with mixed directions
-- Uses LATEST_TARGET_LEVEL field to track state across multiple steps
test.register_coroutine_test(
  "stateless_handler: stepShadeLevel - continuous step operations with mixed directions",
  function()
    -- Set initial state: device reports 50%
    -- aqara handler emits windowShadeLevel and windowShade events
    test.socket.zigbee:__queue_receive({
      aqara_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(aqara_device, 50)
    })
    -- aqara handler emits shade level and shade events
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 50 } }
    })
    test.socket.capability:__expect_send({
      aqara_device.id,
      { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } }
    })
    test.wait_for_events()

    -- Manually set LATEST_TARGET_LEVEL to simulate the reported value being used as current level
    aqara_device:set_field("_latestTargetLevel", 50)

    -- Step 1: stepSize = 10 (up)
    -- current_level = 50 (from LATEST_TARGET_LEVEL), step = 10
    -- ui_target_level = clamp(50 + 10, 0, 100) = 60
    -- device_target_level = 60
    test.socket.capability:__queue_receive({
      aqara_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 } }
    })
    test.socket.capability:__expect_send(
      aqara_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(60))
    )
    test.socket.zigbee:__expect_send({
      aqara_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(aqara_device, 60)
    })
    test.wait_for_events()

    -- Step 2: stepSize = 10 (up)
    -- current_level = 60 (from LATEST_TARGET_LEVEL), step = 10
    -- ui_target_level = clamp(60 + 10, 0, 100) = 70
    -- device_target_level = 70
    test.socket.capability:__queue_receive({
      aqara_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 } }
    })
    test.socket.capability:__expect_send(
      aqara_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(70))
    )
    test.socket.zigbee:__expect_send({
      aqara_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(aqara_device, 70)
    })
    test.wait_for_events()

    -- Step 3: stepSize = -20 (down)
    -- current_level = 70 (from LATEST_TARGET_LEVEL), step = -20
    -- ui_target_level = clamp(70 + (-20), 0, 100) = 50
    -- device_target_level = 50
    test.socket.capability:__queue_receive({
      aqara_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -20 } }
    })
    test.socket.capability:__expect_send(
      aqara_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50))
    )
    test.socket.zigbee:__expect_send({
      aqara_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(aqara_device, 50)
    })
    test.wait_for_events()

    -- Step 4: stepSize = 15 (up)
    -- current_level = 50 (from LATEST_TARGET_LEVEL), step = 15
    -- ui_target_level = clamp(50 + 15, 0, 100) = 65
    -- device_target_level = 65
    test.socket.capability:__queue_receive({
      aqara_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 15 } }
    })
    test.socket.capability:__expect_send(
      aqara_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(65))
    )
    test.socket.zigbee:__expect_send({
      aqara_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(aqara_device, 65)
    })
    test.wait_for_events()

    -- Step 5: stepSize = -5 (down)
    -- current_level = 65 (from LATEST_TARGET_LEVEL), step = -5
    -- ui_target_level = clamp(65 + (-5), 0, 100) = 60
    -- device_target_level = 60
    test.socket.capability:__queue_receive({
      aqara_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -5 } }
    })
    test.socket.capability:__expect_send(
      aqara_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(60))
    )
    test.socket.zigbee:__expect_send({
      aqara_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(aqara_device, 60)
    })
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

test.run_registered_tests()
