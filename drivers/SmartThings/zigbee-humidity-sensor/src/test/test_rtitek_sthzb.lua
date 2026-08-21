-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local PowerConfiguration = clusters.PowerConfiguration
local RelativeHumidity = clusters.RelativeHumidity
local TemperatureMeasurement = clusters.TemperatureMeasurement

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("rtitek-sthzb.yml"),
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "Rti-Tek",
      model = "STHZB",
      server_clusters = { 0x0001, 0x0402, 0x0405, 0xFD22 },
    },
  },
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "STHZB standard temperature report is exposed in Celsius",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        TemperatureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 2630),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main", capabilities.temperatureMeasurement.temperature({ value = 26.3, unit = "C" })
      ),
    },
  },
  { min_api_version = 14 }
)

test.register_message_test(
  "STHZB standard humidity report is exposed as percent",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        RelativeHumidity.attributes.MeasuredValue:build_test_attr_report(mock_device, 5830),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main", capabilities.relativeHumidityMeasurement.humidity({ value = 58.3 })
      ),
    },
  },
  { min_api_version = 14 }
)

test.register_message_test(
  "STHZB standard battery percentage is exposed",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 150),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(75)),
    },
  },
  { min_api_version = 14 }
)

test.register_coroutine_test(
  "STHZB refresh reads standard measurement attributes",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} },
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      TemperatureMeasurement.attributes.MeasuredValue:read(mock_device),
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      RelativeHumidity.attributes.MeasuredValue:read(mock_device),
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device),
    })
    test.wait_for_events()
  end,
  { min_api_version = 14, inner_block_ordering = "relaxed" }
)

test.run_registered_tests()
