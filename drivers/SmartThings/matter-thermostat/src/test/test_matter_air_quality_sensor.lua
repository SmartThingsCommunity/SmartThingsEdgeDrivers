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
local SinglePrecisionFloat = require "st.matter.data_types.SinglePrecisionFloat"

local clusters = require "st.matter.clusters"

local mock_device = test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition("air-purifier-hepa-ac-temperature-humidity-fan-aqs-pm25-tvoc-meas.yml"),
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
                {cluster_id = clusters.AirQuality.ID, cluster_type = "SERVER"},
                {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
                {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
                {cluster_id = clusters.CarbonMonoxideConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
                {cluster_id = clusters.CarbonDioxideConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
                {cluster_id = clusters.NitrogenDioxideConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
                {cluster_id = clusters.OzoneConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
                {cluster_id = clusters.FormaldehydeConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
                {cluster_id = clusters.Pm1ConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
                {cluster_id = clusters.Pm25ConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
                {cluster_id = clusters.Pm10ConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
                {cluster_id = clusters.RadonConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
                {cluster_id = clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
            },
            device_types = {
                {device_type_id = 0x002C, device_type_revision = 1} -- Air Quality Sensor
            }
        }
    }
})

-- create test_init functions
local function initialize_mock_device(generic_mock_device, generic_subscribed_attributes)
    local subscribe_request = nil
    for _, attributes in pairs(generic_subscribed_attributes) do
        for _, attribute in ipairs(attributes) do
            if subscribe_request == nil then
                subscribe_request = attribute:subscribe(generic_mock_device)
            else
                subscribe_request:merge(attribute:subscribe(generic_mock_device))
            end
        end
    end
    test.socket.matter:__expect_send({generic_mock_device.id, subscribe_request})
    test.mock_device.add_test_device(generic_mock_device)
end

local function test_init()
    local subscribed_attributes = {
        [capabilities.relativeHumidityMeasurement.ID] = {
            clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
        },
        [capabilities.temperatureMeasurement.ID] = {
            clusters.TemperatureMeasurement.attributes.MeasuredValue,
            clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
            clusters.TemperatureMeasurement.attributes.MaxMeasuredValue
        },
        [capabilities.airQualityHealthConcern.ID] = {
            clusters.AirQuality.attributes.AirQuality
        },
        [capabilities.finedustSensor.ID] = {
            clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue,
            clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit,
        },
        [capabilities.tvocMeasurement.ID] = {
            clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue,
            clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit,
        },
  }
  initialize_mock_device(mock_device, subscribed_attributes)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Measured value reports should generate events if there is a stored unit",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit:build_test_report_data(
        mock_device, 1, clusters.Pm25ConcentrationMeasurement.types.MeasurementUnitEnum.UGM3
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue:build_test_report_data(
        mock_device, 1, SinglePrecisionFloat(0, 4, .11187500) -- ~17.9
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.fineDustSensor.fineDustLevel({value = 18, unit = "μg/m^3"}))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit:build_test_report_data(
        mock_device, 1, clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.types.MeasurementUnitEnum.PPM
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue:build_test_report_data(
        mock_device, 1, SinglePrecisionFloat(0, -1, .5) -- 0.750 ppm
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.tvocMeasurement.tvocLevel({value = 750, unit = "ppb"}))
    )
  end
)

test.register_coroutine_test(
  "Measured value reports should generate events if stored unit does not match target unit and weight is N/A",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit:build_test_report_data(
        mock_device, 1, clusters.Pm25ConcentrationMeasurement.types.MeasurementUnitEnum.PPM
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue:build_test_report_data(
        mock_device, 1, SinglePrecisionFloat(0, 4, .11187500) -- ~17.9
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.fineDustSensor.fineDustLevel({value = 18, unit = "μg/m^3"}))
    )
  end
)

-- run tests
test.run_registered_tests()