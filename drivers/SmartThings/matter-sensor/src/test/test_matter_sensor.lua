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
      {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
    }
  },
  {
    endpoint_id = 1,
    clusters = {
      {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
      {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "BOTH"},
    },
    device_types = {}
  },
  {
    endpoint_id = 2,
    clusters = {
      {cluster_id = clusters.IlluminanceMeasurement.ID, cluster_type = "SERVER"},
      {cluster_id = clusters.BooleanState.ID, cluster_type = "SERVER"},
    },
    device_types = {}
  },
  {
    endpoint_id = 3,
    clusters = {
      {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER"},
      {cluster_id = clusters.OccupancySensing.ID, cluster_type = "SERVER"},
    },
    device_types = {}
  }
}

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("sensor.yml"),
  endpoints = matter_endpoints
})

local function subscribe_on_init(dev)
  local subscribe_request = clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:subscribe(mock_device)
  subscribe_request:merge(clusters.TemperatureMeasurement.attributes.MeasuredValue:subscribe(mock_device))
  subscribe_request:merge(clusters.TemperatureMeasurement.attributes.MinMeasuredValue:subscribe(mock_device))
  subscribe_request:merge(clusters.TemperatureMeasurement.attributes.MaxMeasuredValue:subscribe(mock_device))
  subscribe_request:merge(clusters.IlluminanceMeasurement.attributes.MeasuredValue:subscribe(mock_device))
  subscribe_request:merge(clusters.BooleanState.attributes.StateValue:subscribe(mock_device))
  subscribe_request:merge(clusters.OccupancySensing.attributes.Occupancy:subscribe(mock_device))
  subscribe_request:merge(clusters.PowerSource.attributes.BatPercentRemaining:subscribe(mock_device))
  return subscribe_request
end

local function test_init()
  test.socket.matter:__expect_send({mock_device.id, subscribe_on_init(mock_device)})
  test.mock_device.add_test_device(mock_device)
  -- don't check the battery for this device because we are using the catch-all "sensor.yml" profile just for testing
  mock_device:set_field("__battery_checked", 1, {persist = true})
  test.set_rpc_version(5)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Relative humidity reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RelativeHumidityMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 4049)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 40 }))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RelativeHumidityMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 4050)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 41 }))
    }
  }
)

test.register_message_test(
  "Temperature reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 40*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 40.0, unit = "C" }))
    }
  }
)

test.register_message_test(
  "Illuminance reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.IlluminanceMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 21370)
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
  "Boolean state reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.BooleanState.server.attributes.StateValue:build_test_report_data(mock_device, 1, false)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.open())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.BooleanState.server.attributes.StateValue:build_test_report_data(mock_device, 1, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.closed())
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

test.register_message_test(
  "Occupancy reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OccupancySensing.attributes.Occupancy:build_test_report_data(mock_device, 1, 1)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OccupancySensing.attributes.Occupancy:build_test_report_data(mock_device, 1, 0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    }
  }
)

local function refresh_commands(dev)
  local req = clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:read(dev)
  req:merge(clusters.TemperatureMeasurement.attributes.MeasuredValue:read(dev))
  req:merge(clusters.TemperatureMeasurement.attributes.MinMeasuredValue:read(dev))
  req:merge(clusters.TemperatureMeasurement.attributes.MaxMeasuredValue:read(dev))
  req:merge(clusters.IlluminanceMeasurement.attributes.MeasuredValue:read(dev))
  req:merge(clusters.BooleanState.attributes.StateValue:read(dev))
  req:merge(clusters.OccupancySensing.attributes.Occupancy:read(dev))
  req:merge(clusters.PowerSource.attributes.BatPercentRemaining:read(dev))
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

test.register_message_test(
  "Min and max temperature attributes set capability constraint",
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
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = 5.00, maximum = 40.00 }, unit = "C" }))
    }
  }
)

test.run_registered_tests()
