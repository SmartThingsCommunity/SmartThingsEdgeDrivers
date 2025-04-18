-- Copyright 2025 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local test = require "integration_test"
local capabilities = require "st.capabilities"

local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"

local mock_device= test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("flow.yml"),
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
        {cluster_id = clusters.FlowMeasurement.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0306, device_type_revision = 1} -- Flow Sensor
      }
    }
  }
})

local subscribed_attributes = {
  clusters.FlowMeasurement.attributes.MeasuredValue,
  clusters.FlowMeasurement.attributes.MinMeasuredValue,
  clusters.FlowMeasurement.attributes.MaxMeasuredValue
}

local function test_init()
  test.mock_device.add_test_device(mock_device)
  local subscribe_request = subscribed_attributes[1]:subscribe(mock_device)
  for i, cluster in ipairs(subscribed_attributes) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Flow reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FlowMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 20*10)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.flowMeasurement.flow({ value = 20.0, unit = "m^3/h" }))
    }
  }
)

test.register_message_test(
  "Min and max flow attributes set capability constraint",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FlowMeasurement.attributes.MinMeasuredValue:build_test_report_data(mock_device, 1, 20)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FlowMeasurement.attributes.MaxMeasuredValue:build_test_report_data(mock_device, 1, 5000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.flowMeasurement.flowRange({ value = { minimum = 2.0, maximum = 500.0 }, unit = "m^3/h" }))
    }
  }
)

local function refresh_commands(dev)
  local req = clusters.FlowMeasurement.attributes.MeasuredValue:read(dev)
  req:merge(clusters.FlowMeasurement.attributes.MinMeasuredValue:read(dev))
  req:merge(clusters.FlowMeasurement.attributes.MaxMeasuredValue:read(dev))
  return req
end

test.register_message_test(
  "Handle received refresh.",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "refresh", component = "main", command = "refresh", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        refresh_commands(mock_device)
      }
    },
  }
)

test.run_registered_tests()
