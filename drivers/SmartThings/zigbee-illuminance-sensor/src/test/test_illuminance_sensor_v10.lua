-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local IlluminanceMeasurement = clusters.IlluminanceMeasurement
local PowerConfiguration = clusters.PowerConfiguration
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local version = require "version"
version.api = 10

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("battery-illuminance.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          server_clusters = {0x0400, 0x0001}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_message_test(
  "Illuminance report should be handled",
  {
     {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_device.id,
          IlluminanceMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 21370)
        }
     },
     {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance({ value = 137 }))
     }
  }
)

test.register_message_test(
  "BatteryPercentRemaining report should be handled",
  {
     {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_device.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 55)
        }
     },
     {
         channel = "capability",
         direction = "send",
         message = mock_device:generate_test_message("main", capabilities.battery.battery(28))
     }
  }
)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          IlluminanceMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 1, 3600, 1)
        }
    )
    test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 0x001E, 0x5460, 1)
        }
    )
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, IlluminanceMeasurement.ID)
        }
    )
    test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
        }
    )
    test.socket.zigbee:__expect_send({ mock_device.id, IlluminanceMeasurement.attributes.MeasuredValue:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) })
  end
)

test.run_registered_tests()
