-- Copyright 2024 SmartThings
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
local uint32 = require "st.matter.data_types.Uint32"

local clusters = require "st.matter.clusters"
clusters.SmokeCoAlarm = require "SmokeCoAlarm"
local version = require "version"
if version.api < 10 then
  clusters.SmokeCoAlarm = require "SmokeCoAlarm"
  clusters.CarbonMonoxideConcentrationMeasurement = require "CarbonMonoxideConcentrationMeasurement"
end

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("smoke-co-temp-humidity-comeas-battery.yml"),
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
        {cluster_id = clusters.SmokeCoAlarm.ID, cluster_type = "SERVER", feature_map = clusters.SmokeCoAlarm.types.Feature.CO_ALARM | clusters.SmokeCoAlarm.types.Feature.SMOKE_ALARM},
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.CarbonMonoxideConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = clusters.CarbonMonoxideConcentrationMeasurement.types.Feature.NUMERIC_MEASUREMENT},
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY},
      },
      device_types = {
        {device_type_id = 0x0076, device_type_revision = 1} -- Smoke CO Alarm
      }
    }
  }
})

local cluster_subscribe_list = {
  clusters.SmokeCoAlarm.attributes.SmokeState,
  clusters.SmokeCoAlarm.attributes.TestInProgress,
  clusters.SmokeCoAlarm.attributes.COState,
  clusters.SmokeCoAlarm.attributes.HardwareFaultAlert,
  clusters.TemperatureMeasurement.attributes.MeasuredValue,
  clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
  clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
  clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
  clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue,
  clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit,
  clusters.PowerSource.attributes.BatPercentRemaining,
}

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  local read_attribute_list = clusters.PowerSource.attributes.AttributeList:read()
  test.socket.matter:__expect_send({mock_device.id, read_attribute_list})
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
    mock_device:expect_metadata_update({ profile = "smoke-co-temp-humidity-comeas-battery" })
  end
)

test.register_coroutine_test(
  "Test that profile does not change when battery percent remaining attribute is not available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 1, {uint32(0)})
      }
    )
  end
)

test.register_coroutine_test(
  "Battery percent reports should generate correct messages",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(mock_device, 1, 150)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.battery.battery(math.floor(150 / 2.0 + 0.5))
      )
    )
  end
)

test.run_registered_tests()
