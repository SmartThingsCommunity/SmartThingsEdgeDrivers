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
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local utils = require "st.utils"
local data_types = require "st.matter.data_types"
local SinglePrecisionFloat = require "st.matter.data_types.SinglePrecisionFloat"

local clusters = require "st.matter.clusters"

local airQualityID = "spacewonder52282.airQuality"
local nitrogenDioxideMeasurementID = "spacewonder52282.nitrogenDioxideMeasurement"
local ozoneMeasurementID = "spacewonder52282.ozoneMeasurement"
test.add_package_capability("air-quality.yml")
test.add_package_capability("nitrogen-dioxide-measurement.yml")
test.add_package_capability("ozone-measurement.yml")
local airQuality = capabilities[airQualityID]
local nitrogenDioxideMeasurement = capabilities[nitrogenDioxideMeasurementID]
local ozoneMeasurement = capabilities[ozoneMeasurementID]

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("air-quality-sensor-custom.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.BasicInformation.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0016, device_type_revision = 1, -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.AirQuality.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.CarbonMonoxideConcentrationMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.CarbonDioxideConcentrationMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.NitrogenDioxideConcentrationMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.OzoneConcentrationMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.FormaldehydeConcentrationMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.Pm1ConcentrationMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.Pm25ConcentrationMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.Pm10ConcentrationMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RadonConcentrationMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID, cluster_type = "SERVER"},
      }
    }
  }
})

local function test_init()
  local subscribed_attributes = {
    [airQualityID] = {
      clusters.AirQuality.attributes.AirQuality
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.TemperatureMeasurement.attributes.MeasuredValue
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.carbonMonoxideMeasurement.ID] = {
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.carbonDioxideMeasurement.ID] = {
      clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [nitrogenDioxideMeasurementID] = {
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasurementUnit
    },
    [ozoneMeasurementID] = {
      clusters.OzoneConcentrationMeasurement.attributes.MeasuredValue,
      clusters.OzoneConcentrationMeasurement.attributes.MeasurementUnit
    },
    [capabilities.formaldehydeMeasurement.ID] = {
      clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue,
      clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.veryFineDustSensor.ID] = {
      clusters.Pm1ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm1ConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.fineDustSensor.ID] = {
      clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.dustSensor.ID] = {
      clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.radonMeasurement.ID] = {
      clusters.RadonConcentrationMeasurement.attributes.MeasuredValue,
      clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.tvocMeasurement.ID] = {
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue,
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit,
    }
  }
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = nil
  for _, attributes in pairs(subscribed_attributes) do
    for _, attribute in ipairs(attributes) do
      if subscribe_request == nil then
        subscribe_request = attribute:subscribe(mock_device)
      else
        subscribe_request:merge(attribute:subscribe(mock_device))
      end
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

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
  "Relative humidity reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RelativeHumidityMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 40*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 40 }))
    }
  }
)

test.register_coroutine_test(
  "Measured value reports should not generate events if there is not a stored unit",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue:build_test_report_data(
        mock_device, 1, SinglePrecisionFloat(0, 4, .11187500) -- ~17.9
      )
    })
  end
)

test.register_coroutine_test(
  "Measured value reports should generate events if there is a stored unit",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit:build_test_report_data(
        mock_device, 1, clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit.PPM
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue:build_test_report_data(
        mock_device, 1, SinglePrecisionFloat(0, 4, .11187500) -- ~17.9
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.formaldehydeMeasurement.formaldehydeLevel({value = 18, unit = "ppm"}))
    )
  end
)

test.register_coroutine_test(
  "AQI reports should generate correct state",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.AirQuality.attributes.AirQuality:build_test_report_data(
        mock_device, 1, 5
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", airQuality.airQuality.veryPoor())
    )
  end
)

test.run_registered_tests()