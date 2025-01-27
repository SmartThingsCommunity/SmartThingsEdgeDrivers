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

local mock_device_common = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("aqs-temp-humidity-co2-pm25-tvoc-meas.yml"),
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

local mock_device_level = test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition("aqs-temp-humidity-all-level.yml"),
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
                {cluster_id = clusters.CarbonMonoxideConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 2},
                {cluster_id = clusters.CarbonDioxideConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 2},
                {cluster_id = clusters.NitrogenDioxideConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 2},
                {cluster_id = clusters.OzoneConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 2},
                {cluster_id = clusters.FormaldehydeConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 2},
                {cluster_id = clusters.Pm1ConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 2},
                {cluster_id = clusters.Pm25ConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 2},
                {cluster_id = clusters.Pm10ConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 2},
                {cluster_id = clusters.RadonConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 2},
                {cluster_id = clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 2},
            },
            device_types = {
                {device_type_id = 0x002C, device_type_revision = 1} -- Air Quality Sensor
            }
        }
    }
})

local mock_device_co = test.mock_device.build_test_matter_device({
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
        {cluster_id = clusters.CarbonMonoxideConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
      },
      device_types = {
        {device_type_id = 0x002C, device_type_revision = 1} -- Air Quality Sensor
      }
    }
  }
})

local mock_device_co2 = test.mock_device.build_test_matter_device({
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
        {cluster_id = clusters.CarbonDioxideConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
      },
      device_types = {
        {device_type_id = 0x002C, device_type_revision = 1} -- Air Quality Sensor
      }
    }
  }
})

local mock_device_tvoc = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("aqs-temp-humidity-tvoc-meas.yml"),
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
        {cluster_id = clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 1},
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

local function test_init_common()
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
  initialize_mock_device(mock_device_common, subscribed_attributes)
end

local function test_init_level()
  local subscribed_attributes = {
    [capabilities.airQualityHealthConcern.ID] = {
      clusters.AirQuality.attributes.AirQuality
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.TemperatureMeasurement.attributes.MeasuredValue,
      clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
      clusters.TemperatureMeasurement.attributes.MaxMeasuredValue
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.carbonMonoxideHealthConcern.ID] = {
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.carbonDioxideHealthConcern.ID] = {
      clusters.CarbonDioxideConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.nitrogenDioxideHealthConcern.ID] = {
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.ozoneHealthConcern.ID] = {
      clusters.OzoneConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.formaldehydeHealthConcern.ID] = {
      clusters.FormaldehydeConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.veryFineDustHealthConcern.ID] = {
      clusters.Pm1ConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.fineDustHealthConcern.ID] = {
      clusters.Pm25ConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.dustHealthConcern.ID] = {
      clusters.Pm10ConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.radonHealthConcern.ID] = {
      clusters.RadonConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.tvocHealthConcern.ID] = {
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue,
    }
  }
  initialize_mock_device(mock_device_level, subscribed_attributes)
end

local function test_init_tvoc()
  local subscribed_attributes = {
    [capabilities.airQualityHealthConcern.ID] = {
      clusters.AirQuality.attributes.AirQuality
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.TemperatureMeasurement.attributes.MeasuredValue,
      clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
      clusters.TemperatureMeasurement.attributes.MaxMeasuredValue
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.tvocMeasurement.ID] = {
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue,
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit,
    },
  }
  initialize_mock_device(mock_device_tvoc, subscribed_attributes)
end

local function test_init_co_co2()
  local attr_co = {
    [capabilities.carbonMonoxideMeasurement.ID] = {
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.carbonMonoxideHealthConcern.ID] = {
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.LevelValue,
    },
  }

  local attr_co2 = {
    [capabilities.carbonDioxideMeasurement.ID] = {
      clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.carbonDioxideHealthConcern.ID] = {
      clusters.CarbonDioxideConcentrationMeasurement.attributes.LevelValue,
    },
  }

  initialize_mock_device(mock_device_co, attr_co)
  initialize_mock_device(mock_device_co2, attr_co2)
end


-- run the profile configuration tests
local function test_aqs_device_type_do_configure(generic_mock_device, expected_profile)
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
  generic_mock_device:expect_metadata_update({ profile = expected_profile })
  generic_mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.register_coroutine_test(
  "Configure should read units from device and profile change as needed",
  function()
    test_aqs_device_type_do_configure(mock_device, "aqs-temp-humidity-all-level-all-meas")
  end
)

test.register_coroutine_test(
  "Configure should read units from device and profile change to common clusters profile if applicable",
  function()
    test_aqs_device_type_do_configure(mock_device_common, "aqs-temp-humidity-co2-pm25-tvoc-meas")
  end,
  { test_init = test_init_common }
)

test.register_coroutine_test(
  "Configure should read units from device and profile change as needed",
  function()
    test_aqs_device_type_do_configure(mock_device_level, "aqs-temp-humidity-all-level")
  end,
  { test_init = test_init_level }
)

test.register_coroutine_test(
  "Configure should not catch co2, only co in the first check",
  function()
    test_aqs_device_type_do_configure(mock_device_co, "aqs-temp-humidity-all-meas")
    test_aqs_device_type_do_configure(mock_device_co2, "aqs-temp-humidity-co2-pm25-tvoc-meas")
  end,
  { test_init = test_init_co_co2 }
)

test.register_coroutine_test(
  "Device should profile to aqs-temp-humidity-tvoc-meas",
  function()
    test_aqs_device_type_do_configure(mock_device_tvoc, "aqs-temp-humidity-tvoc-meas")
  end,
  { test_init = test_init_tvoc }
)


-- run general tests
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

test.register_message_test(
  "Air Quality reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.AirQuality.server.attributes.AirQuality:build_test_report_data(mock_device, 1, 0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.airQualityHealthConcern.airQualityHealthConcern.unknown())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.AirQuality.server.attributes.AirQuality:build_test_report_data(mock_device, 1, 6)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.airQualityHealthConcern.airQualityHealthConcern.hazardous())
    },
  }
)


test.register_coroutine_test(
  "Measured value reports should generate events if there is a stored unit",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit:build_test_report_data(
        mock_device, 1, clusters.CarbonMonoxideConcentrationMeasurement.types.MeasurementUnitEnum.PPM
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue:build_test_report_data(
        mock_device, 1, SinglePrecisionFloat(0, 4, .11187500) -- ~17.9
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.carbonMonoxideMeasurement.carbonMonoxideLevel({value = 18, unit = "ppm"}))
    )
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
      mock_device:generate_test_message("main", capabilities.dustSensor.fineDustLevel({value = 18, unit = "μg/m^3"}))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit:build_test_report_data(
        mock_device, 1, clusters.Pm10ConcentrationMeasurement.types.MeasurementUnitEnum.UGM3
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue:build_test_report_data(
        mock_device, 1, SinglePrecisionFloat(0, 4, .11187500) -- ~17.9
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.dustSensor.dustLevel({value = 18, unit = "μg/m^3"}))
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
  "PM25 reports work for profile with only fineDustLevel capability",
  function()
    test.socket.matter:__queue_receive({
      mock_device_common.id,
      clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit:build_test_report_data(
        mock_device_common, 1, clusters.Pm25ConcentrationMeasurement.types.MeasurementUnitEnum.UGM3
      )
    })
    test.socket.matter:__queue_receive({
      mock_device_common.id,
      clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue:build_test_report_data(
        mock_device_common, 1, SinglePrecisionFloat(0, 4, .11187500) -- ~17.9
      )
    })
    test.socket.capability:__expect_send(
      mock_device_common:generate_test_message("main", capabilities.fineDustSensor.fineDustLevel({value = 18, unit = "μg/m^3"}))
    )
  end,
  { test_init = test_init_common }
)

test.register_coroutine_test(
  "Level value reports should generate events",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.LevelValue:build_test_report_data(
        mock_device, 1, clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.UNKNOWN
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.carbonMonoxideHealthConcern.carbonMonoxideHealthConcern.unknown())
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CarbonDioxideConcentrationMeasurement.attributes.LevelValue:build_test_report_data(
        mock_device, 1, clusters.CarbonDioxideConcentrationMeasurement.types.LevelValueEnum.LOW
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern.good())
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.LevelValue:build_test_report_data(
          mock_device, 1, clusters.NitrogenDioxideConcentrationMeasurement.types.LevelValueEnum.LOW
      )
    })
    test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.nitrogenDioxideHealthConcern.nitrogenDioxideHealthConcern.good())
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.OzoneConcentrationMeasurement.attributes.LevelValue:build_test_report_data(
          mock_device, 1, clusters.OzoneConcentrationMeasurement.types.LevelValueEnum.MEDIUM
      )
    })
    test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.ozoneHealthConcern.ozoneHealthConcern.moderate())
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.FormaldehydeConcentrationMeasurement.attributes.LevelValue:build_test_report_data(
        mock_device, 1, clusters.FormaldehydeConcentrationMeasurement.types.LevelValueEnum.MEDIUM
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.formaldehydeHealthConcern.formaldehydeHealthConcern.moderate())
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Pm1ConcentrationMeasurement.attributes.LevelValue:build_test_report_data(
        mock_device, 1, clusters.Pm1ConcentrationMeasurement.types.LevelValueEnum.HIGH
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.veryFineDustHealthConcern.veryFineDustHealthConcern.unhealthy())
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Pm25ConcentrationMeasurement.attributes.LevelValue:build_test_report_data(
        mock_device, 1, clusters.Pm25ConcentrationMeasurement.types.LevelValueEnum.CRITICAL
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.fineDustHealthConcern.fineDustHealthConcern.hazardous())
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Pm25ConcentrationMeasurement.attributes.LevelValue:build_test_report_data(
        mock_device, 1, clusters.Pm25ConcentrationMeasurement.types.LevelValueEnum.CRITICAL
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.fineDustHealthConcern.fineDustHealthConcern.hazardous())
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Pm10ConcentrationMeasurement.attributes.LevelValue:build_test_report_data(
        mock_device, 1, clusters.Pm10ConcentrationMeasurement.types.LevelValueEnum.CRITICAL
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.dustHealthConcern.dustHealthConcern.hazardous())
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RadonConcentrationMeasurement.attributes.LevelValue:build_test_report_data(
          mock_device, 1, clusters.RadonConcentrationMeasurement.types.LevelValueEnum.CRITICAL
      )
    })
    test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.radonHealthConcern.radonHealthConcern.hazardous())
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue:build_test_report_data(
          mock_device, 1, clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.types.LevelValueEnum.CRITICAL
      )
    })
    test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.tvocHealthConcern.tvocHealthConcern.hazardous())
    )
  end
)

-- run tests
test.run_registered_tests()
