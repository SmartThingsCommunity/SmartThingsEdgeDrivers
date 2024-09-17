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
        endpoint_id = 1,
        clusters = {
          {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.HepaFilterMonitoring.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.ActivatedCarbonFilterMonitoring.ID, cluster_type = "SERVER"},
        }
      }
  }
})

local mock_device_rock = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("air-purifier-hepa-ac-rock-wind.yml"),
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
          {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.HepaFilterMonitoring.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.ActivatedCarbonFilterMonitoring.ID, cluster_type = "SERVER"},
        }
      }
  }
})

local mock_device_ap_aqs = test.mock_device.build_test_matter_device({
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

local mock_device_ap_thermo_aqs = test.mock_device.build_test_matter_device({
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

local mock_device_ap_thermo_aqs_preconfigured = test.mock_device.build_test_matter_device({
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

local cluster_subscribe_list_rock = {
  clusters.FanControl.attributes.FanModeSequence,
  clusters.FanControl.attributes.FanMode,
  clusters.FanControl.attributes.PercentCurrent,
  clusters.FanControl.attributes.WindSupport,
  clusters.FanControl.attributes.WindSetting,
  clusters.FanControl.attributes.RockSupport,
  clusters.FanControl.attributes.RockSetting,
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
  [capabilities.thermostatOperatingState.ID] = {
    clusters.Thermostat.attributes.ThermostatRunningState
  },
  [capabilities.thermostatFanMode.ID] = {
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

local function test_init()
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)

  subscribe_request = cluster_subscribe_list_rock[1]:subscribe(mock_device_rock)
  for i, cluster in ipairs(cluster_subscribe_list_rock) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_rock))
    end
  end
  test.socket.matter:__expect_send({mock_device_rock.id, subscribe_request})
  test.mock_device.add_test_device(mock_device_rock)
end
test.set_test_init_function(test_init)

local function test_init_ap_aqs()
  local subscribe_request_ap_aqs = cluster_subscribe_list[1]:subscribe(mock_device_ap_aqs)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request_ap_aqs:merge(cluster:subscribe(mock_device_ap_aqs))
    end
  end
  test.socket.matter:__expect_send({mock_device_ap_aqs.id, subscribe_request_ap_aqs})
  test.mock_device.add_test_device(mock_device_ap_aqs)
end

local function test_init_ap_thermo_aqs_preconfigured()
  local subscribe_request = nil
  for _, attributes in pairs(cluster_subscribe_list_configured) do
    for _, attribute in ipairs(attributes) do
      if subscribe_request == nil then
        subscribe_request = attribute:subscribe(mock_device)
      else
        subscribe_request:merge(attribute:subscribe(mock_device))
      end
    end
  end
  test.socket.matter:__expect_send({mock_device_ap_thermo_aqs_preconfigured.id, subscribe_request})
  test.mock_device.add_test_device(mock_device_ap_thermo_aqs_preconfigured)
end

local function test_init_ap_thermo_aqs()
  local subscribe_request_ap_aqs = cluster_subscribe_list[1]:subscribe(mock_device_ap_thermo_aqs)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request_ap_aqs:merge(cluster:subscribe(mock_device_ap_thermo_aqs))
    end
  end
  test.socket.matter:__expect_send({mock_device_ap_thermo_aqs.id, subscribe_request_ap_aqs})
  test.mock_device.add_test_device(mock_device_ap_thermo_aqs)
end

test.register_coroutine_test(
  "Test profile change on init for AP and AQS combined device type",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_ap_aqs.id, "doConfigure" })
    mock_device_ap_aqs:expect_metadata_update({ profile = "air-purifier-hepa-ac-aqs-co2-tvoc-meas-co2-radon-level" })
    mock_device_ap_aqs:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  { test_init = test_init_ap_aqs }
)

test.register_coroutine_test(
  "Test profile change on init for AP and Thermo and AQS combined device type",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_ap_thermo_aqs.id, "doConfigure" })
    mock_device_ap_thermo_aqs:expect_metadata_update({ profile = "air-purifier-hepa-ac-rock-wind-thermostat-humidity-fan-heating-only-nostate-nobattery-aqs-pm10-pm25-ch2o-meas-pm10-pm25-ch2o-no2-tvoc-level" })
    mock_device_ap_thermo_aqs:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    print(mock_device_ap_thermo_aqs.profile)
  end,
  { test_init = test_init_ap_thermo_aqs }
)

test.register_coroutine_test(
  "Molecular weight conversion should be handled appropriately in unit_conversion",
  function ()
    test.socket.matter:__queue_receive({
      mock_device_ap_thermo_aqs_preconfigured.id,
      clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit:build_test_report_data(
        mock_device_ap_thermo_aqs_preconfigured, 1, clusters.FormaldehydeConcentrationMeasurement.types.MeasurementUnitEnum.MGM3
      )
    })
    test.socket.matter:__queue_receive({
      mock_device_ap_thermo_aqs_preconfigured.id,
      clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue:build_test_report_data(
        mock_device_ap_thermo_aqs_preconfigured, 1, SinglePrecisionFloat(0, 4, .11187500)
      )
    })
    test.socket.capability:__expect_send(
      mock_device_ap_thermo_aqs_preconfigured:generate_test_message("main", capabilities.formaldehydeMeasurement.formaldehydeLevel({value = 14, unit = "ppm"}))
    )
  end,
  { test_init = test_init_ap_thermo_aqs_preconfigured }
)

test.register_message_test(
  "setAirPurifierFanMode command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "airPurifierFanMode", component = "main", command = "setAirPurifierFanMode", args = { "low" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:write(mock_device, 1, clusters.FanControl.attributes.FanMode.LOW)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "airPurifierFanMode", component = "main", command = "setAirPurifierFanMode", args = { "sleep" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:write(mock_device, 1, clusters.FanControl.attributes.FanMode.LOW)
      }
    },
      {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "airPurifierFanMode", component = "main", command = "setAirPurifierFanMode", args = { "auto" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:write(mock_device, 1, clusters.FanControl.attributes.FanMode.AUTO)
      }
    }
  }
)

test.register_message_test(
  "FanModeSequence send the appropriate commands",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanModeSequence:build_test_report_data(mock_device, 1, 0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.airPurifierFanMode.supportedAirPurifierFanModes({
        capabilities.airPurifierFanMode.airPurifierFanMode.off.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.medium.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME
      }, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanModeSequence:build_test_report_data(mock_device, 1, 1)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.airPurifierFanMode.supportedAirPurifierFanModes({
        capabilities.airPurifierFanMode.airPurifierFanMode.off.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME
      }, {visibility={displayed=false}}))
    },
  }
)

test.register_message_test(
  "Test fan speed commands",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.PercentCurrent:build_test_report_data(mock_device, 1, 10)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanSpeedPercent.percent(10))
    },
      {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "fanSpeedPercent", component = "main", command = "setPercent", args = { 50 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.PercentSetting:write(mock_device, 1, 50)
      }
    }
  }
)

test.register_message_test(
  "Test fan mode handler",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:build_test_report_data(mock_device, 1, clusters.FanControl.attributes.FanMode.OFF)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.airPurifierFanMode.airPurifierFanMode.off())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:build_test_report_data(mock_device, 1, clusters.FanControl.attributes.FanMode.LOW)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.airPurifierFanMode.airPurifierFanMode.low())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:build_test_report_data(mock_device, 1, clusters.FanControl.attributes.FanMode.HIGH)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.airPurifierFanMode.airPurifierFanMode.high())
    },
  }
)

test.register_message_test(
  "Test filter status for HEPA and Activated Carbon filters",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.HepaFilterMonitoring.attributes.ChangeIndication:build_test_report_data(mock_device, 1, clusters.HepaFilterMonitoring.attributes.ChangeIndication.OK)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("hepaFilter", capabilities.filterStatus.filterStatus.normal())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.HepaFilterMonitoring.attributes.ChangeIndication:build_test_report_data(mock_device, 1, clusters.HepaFilterMonitoring.attributes.ChangeIndication.CRITICAL)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("hepaFilter", capabilities.filterStatus.filterStatus.replace())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication:build_test_report_data(mock_device, 1, clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.OK)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("activatedCarbonFilter", capabilities.filterStatus.filterStatus.normal())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication:build_test_report_data(mock_device, 1, clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.CRITICAL)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("activatedCarbonFilter", capabilities.filterStatus.filterStatus.replace())
    },
  }
)

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
        clusters.FanControl.attributes.WindSupport:build_test_report_data(mock_device, 1, 0x03) -- NoWind,  SleepWind (0x0001), and NaturalWind (0x0002)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.windMode.supportedWindModes(supportedFanWind, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.WindSetting:build_test_report_data(mock_device, 1, clusters.FanControl.types.WindSettingMask.SLEEP_WIND)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.windMode.windMode.sleepWind())
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "windMode", component = "main", command = "setWindMode", args = { "naturalWind" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.WindSetting:write(mock_device, 1, clusters.FanControl.types.WindSettingMask.NATURAL_WIND)
      }
    }
  }
)

test.register_message_test(
  "Set percent command should clamp invalid percentage values",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.PercentCurrent:build_test_report_data(mock_device, 1, 255)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanSpeedPercent.percent(100))
    },
  }
)


local supportedFanRock = {
  capabilities.fanOscillationMode.fanOscillationMode.off.NAME,
  capabilities.fanOscillationMode.fanOscillationMode.horizontal.NAME,
  capabilities.fanOscillationMode.fanOscillationMode.vertical.NAME,
  capabilities.fanOscillationMode.fanOscillationMode.swing.NAME
}
test.register_message_test(
  "Test rock mode",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_rock.id,
        clusters.FanControl.attributes.RockSupport:build_test_report_data(mock_device_rock, 1, 0x07) -- off,  RockLeftRight (0x01), RockUpDown (0x02), and RockRound (0x04)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_rock:generate_test_message("main", capabilities.fanOscillationMode.supportedFanOscillationModes(supportedFanRock, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_rock.id,
        clusters.FanControl.attributes.RockSetting:build_test_report_data(mock_device_rock, 1, clusters.FanControl.types.RockBitmap.ROCK_UP_DOWN)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_rock:generate_test_message("main", capabilities.fanOscillationMode.fanOscillationMode.vertical())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_rock.id,
        clusters.FanControl.attributes.RockSetting:build_test_report_data(mock_device_rock, 1, clusters.FanControl.types.RockBitmap.ROCK_LEFT_RIGHT)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_rock:generate_test_message("main", capabilities.fanOscillationMode.fanOscillationMode.horizontal())
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device_rock.id,
        { capability = "fanOscillationMode", component = "main", command = "setFanOscillationMode", args = { "vertical" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device_rock.id,
        clusters.FanControl.attributes.RockSetting:write(mock_device_rock, 1, clusters.FanControl.types.RockBitmap.ROCK_UP_DOWN)
      }
    }
  }
)

test.run_registered_tests()
