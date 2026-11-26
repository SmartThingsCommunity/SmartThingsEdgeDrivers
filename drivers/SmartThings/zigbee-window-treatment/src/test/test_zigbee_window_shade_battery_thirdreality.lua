-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


-- Mock out globals
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local WindowCovering = clusters.WindowCovering

-- Third Reality 3RSB015BZ reports and accepts lift percentage per the ZCL spec
-- (0 = fully open), so it must be handled by the invert-lift-percentage sub-driver.
local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("window-treatment-battery.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Third Reality, Inc",
        model = "3RSB015BZ",
        server_clusters = {0x0000, 0x0001, 0x0102}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
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

test.register_coroutine_test(
  "Lift percentage 0 is reported as fully open",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 0)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
    )
  end,
  {
     min_api_version = 15
  }
)

test.register_coroutine_test(
  "Lift percentage 100 is reported as fully closed",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 100)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
    )
  end,
  {
     min_api_version = 15
  }
)

test.register_coroutine_test(
  "Partial lift percentage is inverted to shade level and settles to partially open",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 20)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(80))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
    )
    test.mock_time.advance_time(2)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
    )
    test.wait_for_events()
  end,
  {
     min_api_version = 15
  }
)

test.register_coroutine_test(
  "setShadeLevel sends inverted lift percentage",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 80 }}
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(mock_device, 20)
    })
  end,
  {
     min_api_version = 15
  }
)

test.run_registered_tests()
