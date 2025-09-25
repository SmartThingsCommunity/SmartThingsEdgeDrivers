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
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local dkjson = require "dkjson"
local uint32 = require "st.matter.data_types.Uint32"
local utils = require "st.utils"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("thermostat-humidity-fan.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"}
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.Thermostat.ID,
          cluster_revision = 5,
          cluster_type = "SERVER",
          feature_map = 3, -- Heat and Cool features
        }
      },
      device_types = {
        {device_type_id = 0x0301, device_type_revision = 1} -- Thermostat
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER", feature_map = 7}
      },
      device_types = {
        {device_type_id = 0x002B, device_type_revision = 1} -- Fan
      }
    },
    {
      endpoint_id = 3,
      clusters = {
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"}
      },
      device_types = {
        {device_type_id = 0x0307, device_type_revision = 1} -- Humidity Sensor
      }
    }
  }
})

local mock_device_disorder_endpoints = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("thermostat-humidity-fan.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"}
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER", feature_map = 7}
      },
      device_types = {
        {device_type_id = 0x002B, device_type_revision = 1} -- Fan
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.Thermostat.ID,
          cluster_revision = 5,
          cluster_type = "SERVER",
          feature_map = 3, -- Heat and Cool features
        }
      },
      device_types = {
        {device_type_id = 0x0301, device_type_revision = 1} -- Thermostat
      }
    },
    {
      endpoint_id = 3,
      clusters = {
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"}
      },
      device_types = {
        {device_type_id = 0x0307, device_type_revision = 1} -- Humidity Sensor
      }
    }
  }
})

local cluster_subscribe_list = {
  clusters.Thermostat.attributes.LocalTemperature,
  clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
  clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
  clusters.Thermostat.attributes.AbsMinCoolSetpointLimit,
  clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit,
  clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
  clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit,
  clusters.Thermostat.attributes.SystemMode,
  clusters.Thermostat.attributes.ThermostatRunningState,
  clusters.Thermostat.attributes.ControlSequenceOfOperation,
  clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
  clusters.FanControl.attributes.FanMode,
  clusters.FanControl.attributes.FanModeSequence,
}

local function get_subscribe_request(device, attribute_list)
  local subscribe_request = attribute_list[1]:subscribe(device)
  for i, cluster in ipairs(attribute_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(device))
    end
  end
  return subscribe_request
end

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  local read_req = clusters.Thermostat.attributes.ControlSequenceOfOperation:read()
  read_req:merge(clusters.FanControl.attributes.FanModeSequence:read())
  read_req:merge(clusters.FanControl.attributes.WindSupport:read())
  read_req:merge(clusters.FanControl.attributes.RockSupport:read())
  read_req:merge(clusters.FanControl.attributes.RockSupport:read())
  read_req:merge(clusters.Thermostat.attributes.AttributeList:read())
  test.socket.matter:__expect_send({mock_device.id, read_req})

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  test.socket.matter:__expect_send({mock_device.id, get_subscribe_request(mock_device, cluster_subscribe_list)})
end
test.set_test_init_function(test_init)

local function test_init_disorder_endpoints()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device_disorder_endpoints)

  test.socket.device_lifecycle:__queue_receive({ mock_device_disorder_endpoints.id, "added" })
  local read_req = clusters.Thermostat.attributes.ControlSequenceOfOperation:read()
  read_req:merge(clusters.FanControl.attributes.FanModeSequence:read())
  read_req:merge(clusters.FanControl.attributes.WindSupport:read())
  read_req:merge(clusters.FanControl.attributes.RockSupport:read())
  read_req:merge(clusters.FanControl.attributes.RockSupport:read())
  read_req:merge(clusters.Thermostat.attributes.AttributeList:read())
  test.socket.matter:__expect_send({mock_device_disorder_endpoints.id, read_req})

  test.socket.device_lifecycle:__queue_receive({ mock_device_disorder_endpoints.id, "init" })
  test.socket.matter:__expect_send({mock_device_disorder_endpoints.id, get_subscribe_request(
    mock_device_disorder_endpoints, cluster_subscribe_list)})
end

-- run the profile configuration tests
local function test_thermostat_device_type_update_modular_profile(generic_mock_device, expected_metadata, subscribe_request)
  test.socket.device_lifecycle:__queue_receive({generic_mock_device.id, "doConfigure"})
  generic_mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  test.wait_for_events()
  test.socket.matter:__queue_receive({
    generic_mock_device.id,
    clusters.Thermostat.attributes.AttributeList:build_test_report_data(generic_mock_device, 1, {uint32(0)})
  })
  generic_mock_device:expect_metadata_update(expected_metadata)

  test.wait_for_events()

  local device_info_copy = utils.deep_copy(generic_mock_device.raw_st_data)
  device_info_copy.profile.id = "thermostat-modular"
  local device_info_json = dkjson.encode(device_info_copy)
  test.socket.device_lifecycle:__queue_receive({ generic_mock_device.id, "infoChanged", device_info_json })
  test.socket.matter:__expect_send({generic_mock_device.id, subscribe_request})
end

local expected_metadata = {
  optional_component_capabilities={
    {
      "main",
      {
        "relativeHumidityMeasurement",
        "fanMode",
        "fanOscillationMode",
        "thermostatHeatingSetpoint",
        "thermostatCoolingSetpoint"
      },
    },
  },
  profile="thermostat-modular",
}

local new_cluster_subscribe_list = {
  clusters.Thermostat.attributes.LocalTemperature,
  clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
  clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
  clusters.Thermostat.attributes.AbsMinCoolSetpointLimit,
  clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit,
  clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
  clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit,
  clusters.Thermostat.attributes.SystemMode,
  clusters.Thermostat.attributes.ThermostatRunningState,
  clusters.Thermostat.attributes.ControlSequenceOfOperation,
  clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
  clusters.FanControl.attributes.FanMode,
  clusters.FanControl.attributes.FanModeSequence,
  clusters.FanControl.attributes.RockSupport,  -- These two attributes will be subscribed to following the profile
  clusters.FanControl.attributes.RockSetting,  -- change since the fanOscillationMode capability will be enabled.
}

test.register_coroutine_test(
  "Profile change on doConfigure lifecycle event no battery & state support",
  function()
    test_thermostat_device_type_update_modular_profile(mock_device, expected_metadata,
      get_subscribe_request(mock_device, new_cluster_subscribe_list))
  end
)

test.register_coroutine_test(
  "Profile change on doConfigure lifecycle event no battery & state support with disorder endpoints",
  function()
    test_thermostat_device_type_update_modular_profile(mock_device_disorder_endpoints, expected_metadata,
      get_subscribe_request(mock_device_disorder_endpoints, new_cluster_subscribe_list))
  end,
  { test_init = test_init_disorder_endpoints }
)

test.run_registered_tests()
