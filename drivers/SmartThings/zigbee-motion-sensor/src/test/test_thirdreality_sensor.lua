-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local Basic = clusters.Basic
local PowerConfiguration = clusters.PowerConfiguration
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local swbuild_payload_older = 0x17 -- "1.0.23"
local swbuild_payload_newer = 0x18 -- "1.0.24"

local mock_device1 = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("motion-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Third Reality, Inc",
        model = "3RMS16BZ",
        server_clusters = {0x0000, 0x0001, 0x0500}
      }
    }
  }
)

local mock_device2 = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("motion-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "THIRDREALITY",
        model = "3RMS16BZ",
        server_clusters = {0x0000, 0x0001, 0x0500}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device1)
  test.mock_device.add_test_device(mock_device2)end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Battery percentage report (55) should be handled -> 55% for a device with FW <= 0x17 ",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device1.id,
        Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device1, swbuild_payload_older)
      }
    )
    test.wait_for_events()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zigbee:__queue_receive(
      {
        mock_device1.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device1, 55)
      }
    )
    test.socket.capability:__expect_send(
      mock_device1:generate_test_message("main", capabilities.battery.battery(55))
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Battery percentage report (120) should be handled -> 100% for a device with FW <= 0x17 ",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device1.id,
        Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device1, swbuild_payload_older)
      }
    )
    test.wait_for_events()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zigbee:__queue_receive(
      {
        mock_device1.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device1, 120)
      }
    )
    test.socket.capability:__expect_send(
        mock_device1:generate_test_message("main", capabilities.battery.battery(100))
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Battery percentage report (110) should be handled -> 55% for a device with FW > 0x17 ",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device2.id,
        Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device1, swbuild_payload_newer)
      }
    )
    test.wait_for_events()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zigbee:__queue_receive(
      {
        mock_device2.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device2, 110)
      }
    )
    test.socket.capability:__expect_send(
      mock_device2:generate_test_message("main", capabilities.battery.battery(55))
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Battery percentage report (240) should be handled -> 100% for a device with FW > 0x17 ",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device2.id,
        Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device1, swbuild_payload_newer)
      }
    )
    test.wait_for_events()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zigbee:__queue_receive(
      {
        mock_device2.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device2, 240)
      }
    )
    test.socket.capability:__expect_send(
      mock_device2:generate_test_message("main", capabilities.battery.battery(100))
    )
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
