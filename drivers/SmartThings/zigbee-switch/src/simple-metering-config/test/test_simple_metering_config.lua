-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local SimpleMetering = clusters.SimpleMetering
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("switch-power-energy.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LEDVANCE",
        model = "PLUG COMPACT EU EM T",
        server_clusters = { 0x0006, 0x0702 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Energy meter report should be handled with default multiplier and divisor",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 1000) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 10, unit = "kWh" }))
    }
  }
)

test.register_message_test(
  "Energy meter report with zero value should be ignored",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 0) }
    }
  }
)

test.register_message_test(
  "Energy meter report with negative value should be ignored",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, -100) }
    }
  }
)

test.run_registered_tests()
