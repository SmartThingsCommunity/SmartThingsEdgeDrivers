-- Copyright 2022 SmartThings
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
local PressureMeasurementCluster = require "PressureMeasurement"

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
      {cluster_id = PressureMeasurementCluster.ID, cluster_type = "SERVER"},
      {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER"},
    }
  }
}

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("pressure-battery.yml"),
  endpoints = matter_endpoints
})

local function subscribe_on_init(dev)
  local subscribe_request = PressureMeasurementCluster.attributes.MeasuredValue:subscribe(mock_device)
  subscribe_request:merge(clusters.PowerSource.attributes.BatPercentRemaining:subscribe(mock_device))
  return subscribe_request
end

local function test_init()
  test.socket.matter:__expect_send({mock_device.id, subscribe_on_init(mock_device)})
  test.mock_device.add_test_device(mock_device)
  -- don't check the battery for this device since we are just testing the "pressure-battery" profile specifically
  mock_device:set_field("__battery_checked", 1, {persist = true})
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Pressure measurement reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        PressureMeasurementCluster.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 1054)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.atmosphericPressureMeasurement.atmosphericPressure({ value = 105, unit = "kPa" }))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        PressureMeasurementCluster.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 1055)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.atmosphericPressureMeasurement.atmosphericPressure({ value = 106, unit = "kPa" }))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        PressureMeasurementCluster.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.atmosphericPressureMeasurement.atmosphericPressure({ value = 0, unit = "kPa" }))
    }
  }
)

test.register_message_test(
  "Battery percent reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(mock_device, 1, 150)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(math.floor(150 / 2.0 + 0.5)))
    }
  }
)


local function refresh_commands(dev)
  local req = clusters.PowerSource.attributes.BatPercentRemaining:read(dev)
  req:merge(PressureMeasurementCluster.attributes.MeasuredValue:read(dev))
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
