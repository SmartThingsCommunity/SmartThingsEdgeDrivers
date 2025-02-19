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
local uint32 = require "st.matter.data_types.Uint32"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("thermostat-batteryLevel.yml"),
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
        {device_type_id = 0x0016, device_type_revision = 1}  -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY},
        {
          cluster_id = clusters.Thermostat.ID,
          cluster_revision=5,
          cluster_type="SERVER",
          feature_map=2, -- Cool feature only.
        },
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0301, device_type_revision = 1} -- Thermostat
      }
    }
  }
})

local cluster_subscribe = {
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
  clusters.PowerSource.attributes.BatChargeLevel,
}

local function test_init()
  local subscribe_request= cluster_subscribe[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe) do
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
  test.socket.matter:__expect_send({mock_device.id, read_req})
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  local attribute_list_read_req = clusters.PowerSource.attributes.AttributeList:read()
  test.socket.matter:__expect_send({mock_device.id, attribute_list_read_req})
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Test profile change when battery percent remaining attribute (attribute ID 12) is available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 1, {uint32(12)})
      }
    )
    mock_device:expect_metadata_update({ profile = "thermostat-cooling-only-nostate" })
  end
)

test.register_coroutine_test(
  "Test profile change when battery level attribute (attribute ID 14) is available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 1, {uint32(14)})
      }
    )
    mock_device:expect_metadata_update({ profile = "thermostat-cooling-only-nostate-batteryLevel" })
  end
)

test.register_coroutine_test(
  "Test that profile does not change when battery percent remaining and battery level attributes are not available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 1, {uint32(10)})
      }
    )
  end
)

test.run_registered_tests()
