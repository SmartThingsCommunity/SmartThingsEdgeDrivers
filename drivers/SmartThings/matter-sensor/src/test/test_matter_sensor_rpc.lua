-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"

local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"

--Note all endpoints are being mapped to the main component
-- in the matter-sensor driver. If any devices require invoke/write
-- requests to support the capabilities/preferences, custom mappings
-- will need to be setup.
local matter_endpoints = {
  {
    endpoint_id = 0,
    clusters = {
      {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
    },
    device_types = {
      device_type_id = 0x0016, device_type_revision = 1, -- RootNode
    }
  },
  {
    endpoint_id = 1,
    clusters = {
      {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "BOTH"},
    },
    device_types = {
      device_type_id = 0x0301, device_type_revision = 1, -- Thermostat
    }
  }
}

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("sensor.yml"),
  endpoints = matter_endpoints
})

local function subscribe_on_init(dev)
  local subscribe_request = clusters.TemperatureMeasurement.attributes.MeasuredValue:subscribe(mock_device)
  subscribe_request:merge(clusters.TemperatureMeasurement.attributes.MinMeasuredValue:subscribe(mock_device))
  subscribe_request:merge(clusters.TemperatureMeasurement.attributes.MaxMeasuredValue:subscribe(mock_device))
  return subscribe_request
end

local function test_init()
  test.socket.matter:__expect_send({mock_device.id, subscribe_on_init(mock_device)})
  test.mock_device.add_test_device(mock_device)
  test.set_rpc_version(3)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Min and max temperature attributes do not set capability constraint when RPC version is less than 5",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.attributes.MinMeasuredValue:build_test_report_data(mock_device, 1, 500)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.attributes.MaxMeasuredValue:build_test_report_data(mock_device, 1, 4000)
      }
    }
  },
  {
     min_api_version = 19
  }
)

test.run_registered_tests()