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
local SinglePrecisionFloat = require "st.matter.data_types.SinglePrecisionFloat"

local clusters = require "st.matter.clusters"

clusters.HepaFilterMonitoring = require "HepaFilterMonitoring"
clusters.ActivatedCarbonFilterMonitoring = require "ActivatedCarbonFilterMonitoring"
clusters.AirQuality = require "AirQuality"
clusters.CarbonMonoxideConcentrationMeasurement = require "CarbonMonoxideConcentrationMeasurement"
clusters.CarbonDioxideConcentrationMeasurement = require "CarbonDioxideConcentrationMeasurement"
clusters.FormaldehydeConcentrationMeasurement = require "FormaldehydeConcentrationMeasurement"
clusters.NitrogenDioxideConcentrationMeasurement = require "NitrogenDioxideConcentrationMeasurement"
clusters.OzoneConcentrationMeasurement = require "OzoneConcentrationMeasurement"
clusters.Pm1ConcentrationMeasurement = require "Pm1ConcentrationMeasurement"
clusters.Pm10ConcentrationMeasurement = require "Pm10ConcentrationMeasurement"
clusters.Pm25ConcentrationMeasurement = require "Pm25ConcentrationMeasurement"
clusters.RadonConcentrationMeasurement = require "RadonConcentrationMeasurement"
clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement = require "TotalVolatileOrganicCompoundsConcentrationMeasurement"

local mock_device = test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition("air-purifier-hepa-ac-wind.yml"),
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
        endpoint_id = 2,
        clusters = {
          {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER", feature_map = 63},
          {cluster_id = clusters.HepaFilterMonitoring.ID, cluster_type = "SERVER", feature_map = 0},
          {cluster_id = clusters.ActivatedCarbonFilterMonitoring.ID, cluster_type = "SERVER", feature_map = 0},
        },
        device_types = {
          {device_type_id = 0x002D, device_type_revision = 1} -- AP
        }
      },
      {
        endpoint_id = 3,
        clusters = {
          {cluster_id = clusters.AirQuality.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.CarbonDioxideConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
          {cluster_id = clusters.RadonConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 2},
          {cluster_id = clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 1},
        },
        device_types = {
          {device_type_id = 0x002C, device_type_revision = 1} -- AQS
        }
      }
    }
})

local cluster_subscribe_list = {
  clusters.FanControl.attributes.FanModeSequence,
  clusters.FanControl.attributes.FanMode,
  clusters.FanControl.attributes.PercentCurrent,
  clusters.FanControl.attributes.WindSupport,
  clusters.FanControl.attributes.WindSetting,
  clusters.HepaFilterMonitoring.attributes.ChangeIndication,
  clusters.HepaFilterMonitoring.attributes.Condition,
  clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication,
  clusters.ActivatedCarbonFilterMonitoring.attributes.Condition,
}

local function test_init_ap_aqs()
    local subscribe_request_ap_aqs = cluster_subscribe_list[1]:subscribe(mock_device)
    for i, cluster in ipairs(cluster_subscribe_list) do
      if i > 1 then
        subscribe_request_ap_aqs:merge(cluster:subscribe(mock_device))
      end
    end
    test.socket.matter:__expect_send({mock_device.id, subscribe_request_ap_aqs})
    test.mock_device.add_test_device(mock_device)
  end
test.set_test_init_function(test_init_ap_aqs)

-- test.register_coroutine_test(
--   "Test read on device_init for Fan Control with Wind Support device",
--   function()
--     test.socket.matter:__queue_receive(mock_device.id,
--         clusters.FanControl.attributes.WindSetting:build_test_report_data(mock_device.id, 2, clusters.FanControl.types.WindSettingMask.SLEEP_WIND)
--     )
--     print("##1")
--     test.socket.capability:__expect_send(
--         mock_device:generate_test_message("main", capabilities.windMode.windMode.noWind())
--     )
--     print("##2")
--   end,
--   {test_init = test_init_ap_aqs}
-- )


local supportedFanWind = {
    capabilities.windMode.windMode.noWind.NAME,
    capabilities.windMode.windMode.sleepWind.NAME,
    capabilities.windMode.windMode.naturalWind.NAME
  }

test.register_message_test(
  "Test wind mode",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.WindSupport:build_test_report_data(mock_device, 1, 0x00) -- NoWind,  SleepWind (0x0001), and NaturalWind (0x0002)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.windMode.supportedWindModes(supportedFanWind, {visibility={displayed=false}}))
    },
  },
  { test_init = test_init_ap_aqs}
)

test.run_registered_tests()
