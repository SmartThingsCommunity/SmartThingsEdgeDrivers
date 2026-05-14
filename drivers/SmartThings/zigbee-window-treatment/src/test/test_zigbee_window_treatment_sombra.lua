-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local WindowCovering = clusters.WindowCovering

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("window-treatment-battery.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Sombra Shades",
        model = "SOMBRA/Z-M",
        server_clusters = {0x000, 0x0003, 0x0004, 0x0005, 0x0102}
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

test.register_message_test(
  "Handle Window Shade level command for Sombra Shades",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        {
          capability = "windowShadeLevel", component = "main",
          command = "setShadeLevel", args = { 33 }
        }
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(33))
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        WindowCovering.server.commands.GoToLiftPercentage(mock_device, 33)
      }
    }
  },
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Handle CurrentPositionLiftPercentage report for Sombra Shades",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 20)
      }
    )
    test.socket.capability:__expect_send(
      {
        mock_device.id,
        {
          capability_id = "windowShadeLevel", component_id = "main",
          attribute_id = "shadeLevel", state = { value = 20 }
        }
      }
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
    min_api_version = 17
  }
)
