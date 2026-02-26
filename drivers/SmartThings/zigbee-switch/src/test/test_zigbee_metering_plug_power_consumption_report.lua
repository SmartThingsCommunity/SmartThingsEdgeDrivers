-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local OnOff = clusters.OnOff
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("switch-power-energy-consumption-report.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "DAWON_DNS",
          model = "PM-B430-ZB",
          server_clusters = { 0x0000, 0x0002, 0x0003, 0x0006, 0x0702, 0x0B04 }
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_message_test(
  "SimpleMetering event should be handled by powerConsumptionReport capability",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 27) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({energy = 27, deltaEnergy = 0.0 }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({value = 0.027, unit = "kWh"}))
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 42) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({energy = 42, deltaEnergy = 15 }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({value = 0.042, unit = "kWh"}))
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
    "InstaneousDemand Report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, SimpleMetering.attributes.InstantaneousDemand:build_test_attr_report(mock_device, 32) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 32.0, unit = "W" }))
      }
    },
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
  "Configure should configure all necessary attributes and refresh device",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, OnOff.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, ElectricalMeasurement.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, SimpleMetering.ID)
    })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        OnOff.attributes.OnOff:configure_reporting(mock_device, 0, 300, 1)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ElectricalMeasurement.attributes.ACPowerMultiplier:configure_reporting(mock_device, 1, 43200, 1)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ElectricalMeasurement.attributes.ACPowerDivisor:configure_reporting(mock_device, 1, 43200, 1)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ElectricalMeasurement.attributes.ActivePower:configure_reporting(mock_device, 5, 3600, 5)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        SimpleMetering.attributes.InstantaneousDemand:configure_reporting(mock_device, 5, 3600, 5)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(mock_device, 5, 3600, 1)
      }
    )

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.ActivePower:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.ACPowerDivisor:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.ACPowerMultiplier:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, SimpleMetering.attributes.InstantaneousDemand:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:read(mock_device) })

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
