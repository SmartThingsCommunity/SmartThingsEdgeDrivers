-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"

test.disable_startup_messages()

local mock_device_all = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("aqs.yml"),
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
        {cluster_id = clusters.AirQuality.ID, cluster_type = "SERVER", feature_map = 3},
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

local mock_device_common = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("aqs.yml"),
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
        {cluster_id = clusters.AirQuality.ID, cluster_type = "SERVER", feature_map = 3},
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.CarbonDioxideConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 1},
        {cluster_id = clusters.Pm25ConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 1},
        {cluster_id = clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 1},
      },
      device_types = {
        {device_type_id = 0x002C, device_type_revision = 1} -- Air Quality Sensor
      }
    }
  }
})

local function test_init_all()
  test.mock_device.add_test_device(mock_device_all)
  test.socket.device_lifecycle:__queue_receive({ mock_device_all.id, "init" })
  test.socket.capability:__expect_send(mock_device_all:generate_test_message("main",
    capabilities.airQualityHealthConcern.supportedAirQualityValues({"unknown", "good", "unhealthy", "moderate", "slightlyUnhealthy"},
    {visibility={displayed=false}}))
  )
  -- on device create, a generic AQS device will be profiled as aqs, thus only subscribing to one attribute
  local subscribe_request = clusters.AirQuality.attributes.AirQuality:subscribe(mock_device_all)
  test.socket.matter:__expect_send({mock_device_all.id, subscribe_request})
end

local function test_init_common()
  test.mock_device.add_test_device(mock_device_common)
  test.socket.device_lifecycle:__queue_receive({ mock_device_common.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_common.id, "init" })
  test.socket.capability:__expect_send(mock_device_common:generate_test_message("main",
    capabilities.airQualityHealthConcern.supportedAirQualityValues({"unknown", "good", "unhealthy", "moderate", "slightlyUnhealthy"},
    {visibility={displayed=false}}))
  )
  -- on device create, a generic AQS device will be profiled as aqs, thus only subscribing to one attribute
  local subscribe_request = clusters.AirQuality.attributes.AirQuality:subscribe(mock_device_common)
  test.socket.matter:__expect_send({mock_device_common.id, subscribe_request})
end

test.set_test_init_function(test_init_all)

local function get_subscribe_request_all()
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
    for _, attribute in pairs(attributes) do
      if subscribe_request == nil then
        subscribe_request = attribute:subscribe(mock_device_all)
      else
        subscribe_request:merge(attribute:subscribe(mock_device_all))
      end
    end
  end
  return subscribe_request
end

local function get_subscribe_request_common()
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
    [capabilities.carbonDioxideMeasurement.ID] = {
      clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.dustSensor.ID] = {
      clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.tvocMeasurement.ID] = {
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue,
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit,
    },
  }
  local subscribe_request = nil
  for _, attributes in pairs(subscribed_attributes) do
    for _, attribute in pairs(attributes) do
      if subscribe_request == nil then
        subscribe_request = attribute:subscribe(mock_device_common)
      else
        subscribe_request:merge(attribute:subscribe(mock_device_common))
      end
    end
  end
  return subscribe_request
end

-- run the profile configuration tests
local function test_aqs_device_type_update_modular_profile(generic_mock_device, expected_metadata, subscribe_request, expected_supported_values_setters)
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
  generic_mock_device:expect_metadata_update(expected_metadata)
  generic_mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  local updated_device_profile = t_utils.get_profile_definition("aqs-modular.yml",
    {enabled_optional_capabilities = expected_metadata.optional_component_capabilities}
  )
  test.socket.device_lifecycle:__queue_receive(generic_mock_device:generate_info_changed({ profile = updated_device_profile }))
  if expected_supported_values_setters ~= nil then
    expected_supported_values_setters()
  end
  test.socket.matter:__expect_send({generic_mock_device.id, subscribe_request})
end

test.register_coroutine_test(
  "Device with modular profile should enable correct optional capabilities - all clusters",
  function()
    local expected_metadata_all = {
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
      profile="aqs-modular-temp-humidity",
    }
    local expected_supported_values_setters = function()
      test.socket.capability:__expect_send(mock_device_all:generate_test_message("main", capabilities.airQualityHealthConcern.supportedAirQualityValues({"unknown", "good", "unhealthy", "moderate", "slightlyUnhealthy"}, {visibility={displayed=false}})))
      test.socket.capability:__expect_send(mock_device_all:generate_test_message("main", capabilities.carbonMonoxideHealthConcern.supportedCarbonMonoxideValues({"unknown", "good", "unhealthy"}, {visibility={displayed=false}})))
      test.socket.capability:__expect_send(mock_device_all:generate_test_message("main", capabilities.carbonDioxideHealthConcern.supportedCarbonDioxideValues({"unknown", "good", "unhealthy"}, {visibility={displayed=false}})))
      test.socket.capability:__expect_send(mock_device_all:generate_test_message("main", capabilities.nitrogenDioxideHealthConcern.supportedNitrogenDioxideValues({"unknown", "good", "unhealthy"}, {visibility={displayed=false}})))
      test.socket.capability:__expect_send(mock_device_all:generate_test_message("main", capabilities.ozoneHealthConcern.supportedOzoneValues({"unknown", "good", "unhealthy"}, {visibility={displayed=false}})))
      test.socket.capability:__expect_send(mock_device_all:generate_test_message("main", capabilities.formaldehydeHealthConcern.supportedFormaldehydeValues({"unknown", "good", "unhealthy"}, {visibility={displayed=false}})))
      test.socket.capability:__expect_send(mock_device_all:generate_test_message("main", capabilities.veryFineDustHealthConcern.supportedVeryFineDustValues({"unknown", "good", "unhealthy"}, {visibility={displayed=false}})))
      test.socket.capability:__expect_send(mock_device_all:generate_test_message("main", capabilities.fineDustHealthConcern.supportedFineDustValues({"unknown", "good", "unhealthy"}, {visibility={displayed=false}})))
      test.socket.capability:__expect_send(mock_device_all:generate_test_message("main", capabilities.dustHealthConcern.supportedDustValues({"unknown", "good", "unhealthy"}, {visibility={displayed=false}})))
      test.socket.capability:__expect_send(mock_device_all:generate_test_message("main", capabilities.radonHealthConcern.supportedRadonValues({"unknown", "good", "unhealthy"}, {visibility={displayed=false}})))
      test.socket.capability:__expect_send(mock_device_all:generate_test_message("main", capabilities.tvocHealthConcern.supportedTvocValues({"unknown", "good", "unhealthy"}, {visibility={displayed=false}})))
    end
    local subscribe_request_all = get_subscribe_request_all()
    test_aqs_device_type_update_modular_profile(mock_device_all, expected_metadata_all, subscribe_request_all, expected_supported_values_setters)
  end,
  { test_init = test_init_all }
)

test.register_coroutine_test(
  "Device with modular profile should enable correct optional capabilities - common clusters",
  function()
    local expected_metadata_common = {
      optional_component_capabilities={
        {
          "main",
          {
            "temperatureMeasurement",
            "relativeHumidityMeasurement",
            "carbonDioxideMeasurement",
            "fineDustSensor",
            "tvocMeasurement",
          },
        },
      },
      profile="aqs-modular-temp-humidity",
    }
    local expected_supported_values_setters = function()
      test.socket.capability:__expect_send(mock_device_common:generate_test_message("main", capabilities.airQualityHealthConcern.supportedAirQualityValues({"unknown", "good", "unhealthy", "moderate", "slightlyUnhealthy"}, {visibility={displayed=false}})))
    end
    local subscribe_request_common = get_subscribe_request_common()
    test_aqs_device_type_update_modular_profile(mock_device_common, expected_metadata_common, subscribe_request_common, expected_supported_values_setters)
  end,
  { test_init = test_init_common }
)

-- run tests
test.run_registered_tests()
