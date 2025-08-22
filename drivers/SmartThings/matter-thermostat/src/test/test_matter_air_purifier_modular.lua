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
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local utils = require "st.utils"
local dkjson = require "dkjson"
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"
local uint32 = require "st.matter.data_types.Uint32"
local version = require "version"

test.disable_startup_messages()

if version.api < 10 then
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
end

local mock_device_basic = test.mock_device.build_test_matter_device({
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
        endpoint_id = 1,
        clusters = {
          {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER", feature_map = 0},
          {cluster_id = clusters.HepaFilterMonitoring.ID, cluster_type = "SERVER", feature_map = 7},
          {cluster_id = clusters.ActivatedCarbonFilterMonitoring.ID, cluster_type = "SERVER", feature_map = 7},
        },
        device_types = {
          {device_type_id = 0x002D, device_type_revision = 1} -- AP
        }
      }
  }
})

local mock_device_ap_thermo_aqs = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("air-purifier-hepa-ac-rock-wind-thermostat-humidity-fan-heating-only-nostate-nobattery-aqs-pm10-pm25-ch2o-meas-pm10-pm25-ch2o-no2-tvoc-level.yml"),
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
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER", feature_map = 63},
        {cluster_id = clusters.HepaFilterMonitoring.ID, cluster_type = "SERVER", feature_map = 7},
        {cluster_id = clusters.ActivatedCarbonFilterMonitoring.ID, cluster_type = "SERVER", feature_map = 7},
      },
      device_types = {
        {device_type_id = 0x002D, device_type_revision = 1} -- AP
      }
    },
    {
      endpoint_id = 3,
      clusters = {
        {cluster_id = clusters.AirQuality.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.NitrogenDioxideConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 14},
        {cluster_id = clusters.Pm25ConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 15},
        {cluster_id = clusters.FormaldehydeConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 15},
        {cluster_id = clusters.Pm10ConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 15},
        {cluster_id = clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID, cluster_type = "SERVER", feature_map = 14},
      },
      device_types = {
        {device_type_id = 0x002C, device_type_revision = 1} -- AQS
      }
    },
    {
      endpoint_id = 4,
      clusters = {
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER", feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0302, device_type_revision = 1} -- Temperature Sensor
      }
    },
    {
      endpoint_id = 6,
      clusters = {
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER", feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0307, device_type_revision = 1} -- Humidity Sensor
      }
    },
    {
      endpoint_id = 7,
      clusters = {
        {cluster_id = clusters.Thermostat.ID, cluster_type = "SERVER", feature_map = 1},
      },
      device_types = {
        {device_type_id = 0x0301, device_type_revision = 1} -- Thermostat
      }
    },
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

local cluster_subscribe_list_configured = {
  [capabilities.temperatureMeasurement.ID] = {
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
    clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
    clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
  },
  [capabilities.relativeHumidityMeasurement.ID] = {
    clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
  },
  [capabilities.thermostatMode.ID] = {
    clusters.Thermostat.attributes.SystemMode,
    clusters.Thermostat.attributes.ControlSequenceOfOperation
  },
  [capabilities.fanMode.ID] = {
    clusters.FanControl.attributes.FanModeSequence,
    clusters.FanControl.attributes.FanMode
  },
  [capabilities.thermostatHeatingSetpoint.ID] = {
    clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
    clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit,
  },
  [capabilities.airPurifierFanMode.ID] = {
    clusters.FanControl.attributes.FanModeSequence,
    clusters.FanControl.attributes.FanMode
  },
  [capabilities.fanSpeedPercent.ID] = {
    clusters.FanControl.attributes.PercentCurrent
  },
  [capabilities.windMode.ID] = {
    clusters.FanControl.attributes.WindSupport,
    clusters.FanControl.attributes.WindSetting,
    clusters.FanControl.attributes.RockSupport,
    clusters.FanControl.attributes.RockSetting,
  },
  [capabilities.filterState.ID] = {
    clusters.HepaFilterMonitoring.attributes.Condition,
    clusters.ActivatedCarbonFilterMonitoring.attributes.Condition
  },
  [capabilities.filterStatus.ID] = {
    clusters.HepaFilterMonitoring.attributes.ChangeIndication,
    clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication
  },
  [capabilities.airQualityHealthConcern.ID] = {
    clusters.AirQuality.attributes.AirQuality
  },
  [capabilities.nitrogenDioxideHealthConcern.ID] = {
    clusters.NitrogenDioxideConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.formaldehydeMeasurement.ID] = {
    clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue,
    clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.formaldehydeHealthConcern.ID] = {
    clusters.FormaldehydeConcentrationMeasurement.attributes.LevelValue,
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
  [capabilities.tvocHealthConcern.ID] = {
    clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue
  }
}

local function test_init_basic()
  test.mock_device.add_test_device(mock_device_basic)
  test.socket.device_lifecycle:__queue_receive({ mock_device_basic.id, "added" })
  local read_attributes = {
    clusters.Thermostat.attributes.ControlSequenceOfOperation,
    clusters.FanControl.attributes.FanModeSequence,
    clusters.FanControl.attributes.WindSupport,
    clusters.FanControl.attributes.RockSupport,
  }
  local read_request = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  for _, clus in ipairs(read_attributes) do
    read_request:merge(clus:read(mock_device_basic))
  end
  test.socket.matter:__expect_send({ mock_device_basic.id, read_request })

  test.socket.device_lifecycle:__queue_receive({ mock_device_basic.id, "init" })
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_basic)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_basic))
    end
  end
  test.socket.matter:__expect_send({mock_device_basic.id, subscribe_request})
end

local function test_init_ap_thermo_aqs_preconfigured()
  test.mock_device.add_test_device(mock_device_ap_thermo_aqs)
  test.socket.device_lifecycle:__queue_receive({ mock_device_ap_thermo_aqs.id, "added" })
  local read_attributes = {
    clusters.Thermostat.attributes.AttributeList,
    clusters.Thermostat.attributes.ControlSequenceOfOperation,
    clusters.FanControl.attributes.FanModeSequence,
    clusters.FanControl.attributes.WindSupport,
    clusters.FanControl.attributes.RockSupport,
  }
  local read_request = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  for _, clus in ipairs(read_attributes) do
    read_request:merge(clus:read(mock_device_ap_thermo_aqs))
  end
  test.socket.matter:__expect_send({ mock_device_ap_thermo_aqs.id, read_request })

  test.socket.device_lifecycle:__queue_receive({ mock_device_ap_thermo_aqs.id, "init" })
  local subscribe_request = nil
  for _, attributes in pairs(cluster_subscribe_list_configured) do
    for _, attribute in ipairs(attributes) do
      if subscribe_request == nil then
        subscribe_request = attribute:subscribe(mock_device_ap_thermo_aqs)
      else
        subscribe_request:merge(attribute:subscribe(mock_device_ap_thermo_aqs))
      end
    end
  end
  test.socket.matter:__expect_send({mock_device_ap_thermo_aqs.id, subscribe_request})
end

local expected_update_metadata= {
  optional_component_capabilities={
    {
      "main",
      {},
    },
    {
      "activatedCarbonFilter",
      {
        "filterState",
        "filterStatus",
      },
    },
    {
      "hepaFilter",
      {
        "filterState",
        "filterStatus",
      },
    },
  },
  profile="air-purifier-modular",
}

local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_basic)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_basic))
    end
  end

test.register_coroutine_test(
  "Test profile change on init for basic Air Purifier device",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_basic.id, "doConfigure" })
    test.socket.matter:__queue_receive({
      mock_device_basic.id,
      clusters.Thermostat.attributes.AttributeList:build_test_report_data(mock_device_basic, 1, {uint32(0)})
    })
    mock_device_basic:expect_metadata_update(expected_update_metadata)
    mock_device_basic:expect_metadata_update({ provisioning_state = "PROVISIONED" })

    test.wait_for_events()

    local device_info_copy = utils.deep_copy(mock_device_basic.raw_st_data)
    device_info_copy.profile.id = "air-purifier-modular"
    local device_info_json = dkjson.encode(device_info_copy)
    test.socket.device_lifecycle:__queue_receive({ mock_device_basic.id, "infoChanged", device_info_json })
    test.socket.matter:__expect_send({mock_device_basic.id, subscribe_request})
  end,
  { test_init = test_init_basic }
)

local expected_update_metadata= {
  optional_component_capabilities={
    {
      "main",
      {
        "relativeHumidityMeasurement",
        "temperatureMeasurement",
        "fanOscillationMode",
        "windMode",
        "thermostatMode",
        "thermostatHeatingSetpoint",
        "airQualityHealthConcern",
        "dustSensor",
        "fineDustSensor",
        "formaldehydeMeasurement",
        "dustHealthConcern",
        "fineDustHealthConcern",
        "formaldehydeHealthConcern",
        "nitrogenDioxideHealthConcern",
        "tvocHealthConcern",
      },
    },
    {
      "activatedCarbonFilter",
      {
        "filterState",
        "filterStatus",
      },
    },
    {
      "hepaFilter",
      {
        "filterState",
        "filterStatus",
      },
    },
  },
  profile="air-purifier-modular",
}

local subscribe_request = nil
for _, attributes in pairs(cluster_subscribe_list_configured) do
  for _, attribute in ipairs(attributes) do
    if subscribe_request == nil then
      subscribe_request = attribute:subscribe(mock_device_ap_thermo_aqs)
    else
      subscribe_request:merge(attribute:subscribe(mock_device_ap_thermo_aqs))
    end
  end
end

test.register_coroutine_test(
  "Test profile change on init for AP and Thermo and AQS combined device type",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_ap_thermo_aqs.id, "doConfigure" })
    mock_device_ap_thermo_aqs:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device_ap_thermo_aqs.id,
      clusters.Thermostat.attributes.AttributeList:build_test_report_data(mock_device_ap_thermo_aqs, 1, {uint32(0)})
    })
    mock_device_ap_thermo_aqs:expect_metadata_update(expected_update_metadata)

    test.wait_for_events()

    local device_info_copy = utils.deep_copy(mock_device_ap_thermo_aqs.raw_st_data)
    device_info_copy.profile.id = "air-purifier-modular"
    local device_info_json = dkjson.encode(device_info_copy)
    test.socket.device_lifecycle:__queue_receive({ mock_device_ap_thermo_aqs.id, "infoChanged", device_info_json })
    test.socket.matter:__expect_send({mock_device_ap_thermo_aqs.id, subscribe_request})
  end,
  { test_init = test_init_ap_thermo_aqs_preconfigured }
)

test.run_registered_tests()
