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

local clusters = require "st.matter.clusters"
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local utils = require "st.utils"

-- Temperature values are converted to Celsius by the hub before reaching the driver for rpc > 5.
-- This test file is meant to verify that the driver converts Fahrenheit values > 40 degrees from F to C for rpc <= 5.
test.set_rpc_version(5)

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
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0016, device_type_revision = 1, -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER"},
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

local function test_init()
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
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
    clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
    clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
    clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
    clusters.FanControl.attributes.FanMode,
    clusters.FanControl.attributes.FanModeSequence,
    clusters.PowerSource.attributes.BatPercentRemaining,
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Setting the heating setpoint to a Fahrenheit value should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 90 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 1,
          utils.round((90 - 32) * (5 / 9.0) * 100))
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 41 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 1,
          utils.round((41 - 32) * (5 / 9.0) * 100))
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 35 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 1, 35 * 100)
      }
    }
  }
)

test.run_registered_tests()
