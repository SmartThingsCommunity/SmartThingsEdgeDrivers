-- Copyright 2023 SmartThings
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
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"

local mock_device_humidity_battery = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("humidity-batteryLevel.yml"),
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
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
      },
      device_types = {}
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 2},
      },
      device_types = {}
    }
  }
})

local mock_device_humidity_no_battery = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("humidity-battery.yml"),
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
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
      },
      device_types = {}
    }
  }
})

local mock_device_temp_humidity = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("temperature-humidity.yml"),
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
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
      },
      device_types = {}
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "BOTH"},
      },
      device_types = {}
    }
  }
})

local cluster_subscribe_list_humidity_battery = {
  clusters.PowerSource.attributes.BatChargeLevel,
  clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
}

local cluster_subscribe_list_humidity_no_battery = {
  clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
}

local cluster_subscribe_list_temp_humidity = {
  clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
  clusters.TemperatureMeasurement.attributes.MeasuredValue,
  clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
  clusters.TemperatureMeasurement.attributes.MaxMeasuredValue
}

local function test_init_humidity_battery()
  local subscribe_request_humidity_battery = cluster_subscribe_list_humidity_battery[1]:subscribe(mock_device_humidity_battery)
  for i, cluster in ipairs(cluster_subscribe_list_humidity_battery) do
    if i > 1 then
      subscribe_request_humidity_battery:merge(cluster:subscribe(mock_device_humidity_battery))
    end
  end

  test.socket.matter:__expect_send({mock_device_humidity_battery.id, subscribe_request_humidity_battery})
  test.mock_device.add_test_device(mock_device_humidity_battery)

  test.socket.device_lifecycle:__queue_receive({ mock_device_humidity_battery.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_humidity_battery.id, "doConfigure" })
  mock_device_humidity_battery:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  local read_attribute_list = clusters.PowerSource.attributes.AttributeList:read()
  test.socket.matter:__expect_send({mock_device_humidity_battery.id, read_attribute_list})
end

local function test_init_humidity_no_battery()
  local subscribe_request_humidity_no_battery = cluster_subscribe_list_humidity_no_battery[1]:subscribe(mock_device_humidity_no_battery)
  for i, cluster in ipairs(cluster_subscribe_list_humidity_no_battery) do
    if i > 1 then
      subscribe_request_humidity_no_battery:merge(cluster:subscribe(mock_device_humidity_no_battery))
    end
  end

  test.socket.matter:__expect_send({mock_device_humidity_no_battery.id, subscribe_request_humidity_no_battery})
  test.mock_device.add_test_device(mock_device_humidity_no_battery)

  test.socket.device_lifecycle:__queue_receive({ mock_device_humidity_no_battery.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_humidity_no_battery.id, "doConfigure" })
  mock_device_humidity_no_battery:expect_metadata_update({ profile = "humidity" })
  mock_device_humidity_no_battery:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function test_init_temp_humidity()
  local subscribe_request_temp_humidity = cluster_subscribe_list_temp_humidity[1]:subscribe(mock_device_temp_humidity)
  for i, cluster in ipairs(cluster_subscribe_list_temp_humidity) do
    if i > 1 then
      subscribe_request_temp_humidity:merge(cluster:subscribe(mock_device_temp_humidity))
    end
  end

  test.socket.matter:__expect_send({mock_device_temp_humidity.id, subscribe_request_temp_humidity})
  test.mock_device.add_test_device(mock_device_temp_humidity)

  test.socket.device_lifecycle:__queue_receive({ mock_device_temp_humidity.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_temp_humidity.id, "doConfigure" })
  mock_device_temp_humidity:expect_metadata_update({ profile = "temperature-humidity" })
  mock_device_temp_humidity:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.register_coroutine_test(
  "Test profile change on init for humidity sensor with battery",
  function()
  end,
  { test_init = test_init_humidity_battery }
)

test.register_coroutine_test(
  "Test profile change on init for humidity sensor without battery",
  function()
  end,
  { test_init = test_init_humidity_no_battery }
)

test.register_coroutine_test(
  "Test profile change on init for temperature-humidity sensor",
  function()
  end,
  { test_init = test_init_temp_humidity }
)

test.run_registered_tests()
