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
local uint32 = require "st.matter.data_types.Uint32"

local clusters = require "st.matter.clusters"

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

local function test_init()
  mock_device:set_field("MIN_SETPOINT_DEADBAND_CHECKED", 1, {persist = true})
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  local read_req = clusters.Thermostat.attributes.ControlSequenceOfOperation:read()
  read_req:merge(clusters.FanControl.attributes.FanModeSequence:read())
  read_req:merge(clusters.FanControl.attributes.WindSupport:read())
  read_req:merge(clusters.FanControl.attributes.RockSupport:read())
  read_req:merge(clusters.FanControl.attributes.RockSupport:read())
  read_req:merge(clusters.Thermostat.attributes.AttributeList:read())
  test.socket.matter:__expect_send({mock_device.id, read_req})
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Profile change on doConfigure lifecycle event no battery & state support",
  function()
    mock_device:set_field("__THERMOSTAT_RUNNING_STATE_SUPPORT", false)
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
    mock_device:expect_metadata_update({ profile = "thermostat-humidity-fan-nostate-nobattery" })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.run_registered_tests()
