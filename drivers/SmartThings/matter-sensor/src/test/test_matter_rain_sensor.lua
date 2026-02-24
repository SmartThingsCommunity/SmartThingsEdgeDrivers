-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"
local version = require "version"

if version.api < 11 then
  clusters.BooleanStateConfiguration = require "embedded_clusters.BooleanStateConfiguration"
end

local mock_device_rain = test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition("rain-fault.yml"),
    manufacturer_info = {
      vendor_id = 0x0000,
      product_id = 0x0000,
    },
    endpoints = {
      {
        endpoint_id = 0,
        clusters = {
          {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
        },
        device_types = {
          {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
        }
      },
      {
        endpoint_id = 1,
        clusters = {
          {cluster_id = clusters.BooleanState.ID, cluster_type = "SERVER", feature_map = 0},
          {cluster_id = clusters.BooleanStateConfiguration.ID, cluster_type = "SERVER", feature_map = 31},
        },
        device_types = {
          {device_type_id = 0x0044, device_type_revision = 1} -- Rain Sensor
        }
      }
    }
})

local subscribed_attributes = {
  clusters.BooleanState.attributes.StateValue,
  clusters.BooleanStateConfiguration.attributes.SensorFault,
}

local function test_init_rain()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device_rain)
  local subscribe_request = subscribed_attributes[1]:subscribe(mock_device_rain)
  for i, cluster in ipairs(subscribed_attributes) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_rain))
    end
  end
  test.socket.device_lifecycle:__queue_receive({ mock_device_rain.id, "init" })
  test.socket.matter:__expect_send({mock_device_rain.id, clusters.BooleanStateConfiguration.attributes.SupportedSensitivityLevels:read(mock_device_rain, 1)})
  test.socket.matter:__expect_send({mock_device_rain.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_rain.id, "doConfigure" })
  mock_device_rain:expect_metadata_update({ profile = "rain-fault-rainSensitivity" })
  mock_device_rain:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end
test.set_test_init_function(test_init_rain)

test.register_message_test(
  "Boolean state rain detection reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_rain.id,
        clusters.BooleanState.server.attributes.StateValue:build_test_report_data(mock_device_rain, 1, false)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_rain:generate_test_message("main", capabilities.rainSensor.rain.undetected())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_rain.id,
        clusters.BooleanState.server.attributes.StateValue:build_test_report_data(mock_device_rain, 1, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_rain:generate_test_message("main", capabilities.rainSensor.rain.detected())
    }
  }
)

test.register_message_test(
  "Test hardware fault alert handler",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_rain.id,
        clusters.BooleanStateConfiguration.attributes.SensorFault:build_test_report_data(mock_device_rain, 1, 0x1)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_rain:generate_test_message("main", capabilities.hardwareFault.hardwareFault.detected())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_rain.id,
        clusters.BooleanStateConfiguration.attributes.SensorFault:build_test_report_data(mock_device_rain, 1, 0x0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_rain:generate_test_message("main", capabilities.hardwareFault.hardwareFault.clear())
    }
  }
)

test.run_registered_tests()
