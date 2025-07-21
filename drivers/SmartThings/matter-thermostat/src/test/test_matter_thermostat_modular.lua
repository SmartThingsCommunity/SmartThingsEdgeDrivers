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
local utils = require "st.utils"
local dkjson = require "dkjson"

local clusters = require "st.matter.clusters"

test.set_rpc_version(8)

local mock_device_basic = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("thermostat-humidity-fan.yml"),
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
        device_type_id = 0x0016, device_type_revision = 1, -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER", feature_map = 0},
        {
          cluster_id = clusters.Thermostat.ID,
          cluster_revision=5,
          cluster_type="SERVER",
          feature_map=3, -- Heat and Cool features
        },
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER"},
      }
    }
  }
})

-- create test_init functions
local function initialize_mock_device(generic_mock_device, generic_subscribed_attributes)
  local subscribe_request = generic_subscribed_attributes[1]:subscribe(generic_mock_device)
  for i, cluster in ipairs(generic_subscribed_attributes) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(generic_mock_device))
    end
  end
  test.socket.matter:__expect_send({generic_mock_device.id, subscribe_request})
  test.mock_device.add_test_device(generic_mock_device)
  return subscribe_request
end

local subscribe_request_basic
local function test_init()
  local subscribed_attributes = {
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
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
    clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
    clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
    clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
    clusters.FanControl.attributes.FanMode,
    clusters.FanControl.attributes.FanModeSequence,
    clusters.PowerSource.attributes.BatPercentRemaining,
  }
  subscribe_request_basic = initialize_mock_device(mock_device_basic, subscribed_attributes)
end

-- run the profile configuration tests
local function test_thermostat_device_type_update_modular_profile(generic_mock_device, expected_metadata, subscribe_request)
  test.socket.device_lifecycle:__queue_receive({generic_mock_device.id, "doConfigure"})
  generic_mock_device:expect_metadata_update(expected_metadata)
  generic_mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
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
        "thermostatHeatingSetpoint",
        "thermostatCoolingSetpoint"
      },
    },
  },
  profile="thermostat-modular",
}

test.register_coroutine_test(
  "Device with modular profile should enable correct optional capabilities",
  function()
    mock_device_basic:set_field("__BATTERY_SUPPORT", "NO_BATTERY") -- since we're assuming this would have happened during device_added in this case.
    mock_device_basic:set_field("__THERMOSTAT_RUNNING_STATE_SUPPORT", false) -- since we're assuming this would have happened during device_added in this case.
    test_thermostat_device_type_update_modular_profile(mock_device_basic, expected_metadata, subscribe_request_basic)
  end,
  { test_init = test_init }
)

-- run tests
test.run_registered_tests()
