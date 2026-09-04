-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement
local RelativeHumidity = clusters.RelativeHumidity
local PressureMeasurement = clusters.PressureMeasurement

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("sonoff-humidity-temp-press-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "SONOFF",
        model = "SNZB-02M",
        server_clusters = { 0x0001, 0x0402, 0x0405, 0x0403 }
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
  "Pressure report above 2000 should be divided by 1000",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        PressureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 10000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.atmosphericPressureMeasurement.atmosphericPressure({ value = 10.0, unit = "kPa" }))
    }
  },
  {
    min_api_version = 14
  }
)

test.register_message_test(
  "Pressure report at or below 2000 should be divided by 10",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        PressureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 960)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.atmosphericPressureMeasurement.atmosphericPressure({ value = 96.0, unit = "kPa" }))
    }
  },
  {
    min_api_version = 14
  }
)

test.register_message_test(
  "Refresh should read temperature, humidity, pressure and battery",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, TemperatureMeasurement.attributes.MeasuredValue:read(mock_device) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, RelativeHumidity.attributes.MeasuredValue:read(mock_device) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, PressureMeasurement.attributes.MeasuredValue:read(mock_device) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) }
    }
  },
  {
    inner_block_ordering = "relaxed",
    min_api_version = 14
  }
)

test.run_registered_tests()
