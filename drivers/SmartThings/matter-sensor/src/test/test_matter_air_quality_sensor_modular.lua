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

local clusters = require "st.matter.clusters"

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

test.set_rpc_version(8)

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("aqs-temp-humidity-all-level-all-meas.yml"),
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
    [capabilities.carbonMonoxideMeasurement.ID] = {
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.carbonMonoxideHealthConcern.ID] = {
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.carbonDioxideMeasurement.ID] = {
      clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.carbonDioxideHealthConcern.ID] = {
      clusters.CarbonDioxideConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.nitrogenDioxideMeasurement.ID] = {
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasurementUnit
    },
    [capabilities.nitrogenDioxideHealthConcern.ID] = {
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.ozoneMeasurement.ID] = {
      clusters.OzoneConcentrationMeasurement.attributes.MeasuredValue,
      clusters.OzoneConcentrationMeasurement.attributes.MeasurementUnit
    },
    [capabilities.ozoneHealthConcern.ID] = {
      clusters.OzoneConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.formaldehydeMeasurement.ID] = {
      clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue,
      clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.formaldehydeHealthConcern.ID] = {
      clusters.FormaldehydeConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.veryFineDustSensor.ID] = {
      clusters.Pm1ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm1ConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.veryFineDustHealthConcern.ID] = {
      clusters.Pm1ConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.fineDustHealthConcern.ID] = {
      clusters.Pm25ConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.dustSensor.ID] = {
      clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit,
      clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.dustHealthConcern.ID] = {
      clusters.Pm10ConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.radonMeasurement.ID] = {
      clusters.RadonConcentrationMeasurement.attributes.MeasuredValue,
      clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.radonHealthConcern.ID] = {
      clusters.RadonConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.tvocMeasurement.ID] = {
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue,
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.tvocHealthConcern.ID] = {
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue,
    },
  }
  initialize_mock_device(mock_device, subscribed_attributes)
end
test.set_test_init_function(test_init)

-- run the profile configuration tests
local function test_aqs_device_type_do_configure(generic_mock_device, expected_metadata, subscribe_request)
  test.socket.device_lifecycle:__queue_receive({generic_mock_device.id, "doConfigure"})
  test.socket.matter:__expect_send({generic_mock_device.id, clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit:read()})
  test.socket.matter:__expect_send({generic_mock_device.id, clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit:read()})
  test.socket.matter:__expect_send({generic_mock_device.id, clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasurementUnit:read()})
  test.socket.matter:__expect_send({generic_mock_device.id, clusters.OzoneConcentrationMeasurement.attributes.MeasurementUnit:read()})
  test.socket.matter:__expect_send({generic_mock_device.id, clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit:read()})
  test.socket.matter:__expect_send({generic_mock_device.id, clusters.Pm1ConcentrationMeasurement.attributes.MeasurementUnit:read()})
  test.socket.matter:__expect_send({generic_mock_device.id, clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit:read()})
  test.socket.matter:__expect_send({generic_mock_device.id, clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit:read()})
  test.socket.matter:__expect_send({generic_mock_device.id, clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit:read()})
  test.socket.matter:__expect_send({generic_mock_device.id, clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit:read()})
  test.socket.matter:__expect_send({generic_mock_device.id, subscribe_request})
  generic_mock_device:expect_metadata_update(expected_metadata)
  generic_mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local expected_metadata = {
  optional_component_capabilities={
    {
      "main",
      {
        "temperatureMeasurement",
        "relativeHumidityMeasurement",
        "carbonMonoxideMeasurement",
        "carbonDioxideMeasurement",
        "nitrogenDioxideMeasurement",
        "ozoneMeasurement",
        "formaldehydeMeasurement",
        "veryFineDustSensor",
        "fineDustSensor",
        "dustSensor",
        "radonMeasurement",
        "tvocMeasurement",
        "carbonMonoxideHealthConcern",
        "carbonDioxideHealthConcern",
        "nitrogenDioxideHealthConcern",
        "ozoneHealthConcern",
        "formaldehydeHealthConcern",
        "veryFineDustHealthConcern",
        "fineDustHealthConcern",
        "dustHealthConcern",
        "radonHealthConcern",
        "tvocHealthConcern",
      },
    },
  },
  profile="aqs-modular",
}

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
  [capabilities.carbonMonoxideMeasurement.ID] = {
    clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue,
    clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.carbonMonoxideHealthConcern.ID] = {
    clusters.CarbonMonoxideConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.carbonDioxideMeasurement.ID] = {
    clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue,
    clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.carbonDioxideHealthConcern.ID] = {
    clusters.CarbonDioxideConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.nitrogenDioxideMeasurement.ID] = {
    clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasuredValue,
    clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasurementUnit
  },
  [capabilities.nitrogenDioxideHealthConcern.ID] = {
    clusters.NitrogenDioxideConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.ozoneMeasurement.ID] = {
    clusters.OzoneConcentrationMeasurement.attributes.MeasuredValue,
    clusters.OzoneConcentrationMeasurement.attributes.MeasurementUnit
  },
  [capabilities.ozoneHealthConcern.ID] = {
    clusters.OzoneConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.formaldehydeMeasurement.ID] = {
    clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue,
    clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.formaldehydeHealthConcern.ID] = {
    clusters.FormaldehydeConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.veryFineDustSensor.ID] = {
    clusters.Pm1ConcentrationMeasurement.attributes.MeasuredValue,
    clusters.Pm1ConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.veryFineDustHealthConcern.ID] = {
    clusters.Pm1ConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.fineDustHealthConcern.ID] = {
    clusters.Pm25ConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.dustSensor.ID] = {
    clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue,
    clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit,
    clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue,
    clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.dustHealthConcern.ID] = {
    clusters.Pm10ConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.radonMeasurement.ID] = {
    clusters.RadonConcentrationMeasurement.attributes.MeasuredValue,
    clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.radonHealthConcern.ID] = {
    clusters.RadonConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.tvocMeasurement.ID] = {
    clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue,
    clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.tvocHealthConcern.ID] = {
    clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue,
  },
}

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

test.register_coroutine_test(
  "Device with modular profile should enabled correct optional capabilities - all clusters",
  function()
    test_aqs_device_type_do_configure(mock_device, expected_metadata, subscribe_request)
  end
)

-- run tests
test.run_registered_tests()
