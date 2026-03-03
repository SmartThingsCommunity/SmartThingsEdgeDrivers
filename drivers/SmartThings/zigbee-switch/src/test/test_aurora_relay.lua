-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local constants = require "st.zigbee.constants"

local OnOff = clusters.OnOff
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("switch-power.yml"),
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "Develco Products A/S",
      model = "Smart16ARelay51AU",
      server_clusters = { 0x0B04, 0x0702, 0x0006 },
    }
  }
})

local function test_init()
  mock_device:set_field("_configuration_version", 1, {persist = true})
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Refresh necessary attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.ActivePower:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.ACPowerDivisor:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.ACPowerMultiplier:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, SimpleMetering.attributes.InstantaneousDemand:read(mock_device) })
  end,
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Capability command On should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_cmd_id = "on" }
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, OnOff.commands.On(mock_device) }
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Capability command Off should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_cmd_id = "off" }
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, OnOff.commands.Off(mock_device) }
    }
  },
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle Power meter",
  function()
    mock_device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1, { persist = true })
    mock_device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 1, { persist = true })

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      SimpleMetering.attributes.InstantaneousDemand:build_test_attr_report(mock_device, 60)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 60.0, unit = "W" }))
    )

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_device, 60)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 60.0, unit = "W" }))
    )
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
