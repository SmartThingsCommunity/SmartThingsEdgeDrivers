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
clusters.SmokeCoAlarm = require "SmokeCoAlarm"
local version = require "version"
if version.api < 10 then
  clusters.SmokeCoAlarm = require "SmokeCoAlarm"
  clusters.CarbonMonoxideConcentrationMeasurement = require "CarbonMonoxideConcentrationMeasurement"
end

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("smoke-co-temp-humidity-comeas.yml"),
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
  clusters.SmokeCoAlarm.attributes.BatteryAlert,
  clusters.TemperatureMeasurement.attributes.MeasuredValue,
  clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
  clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
  clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
  clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue,
  clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit,
  clusters.PowerSource.attributes.BatChargeLevel,
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
  mock_device:expect_metadata_update({ profile = "smoke-co-temp-humidity-comeas" })
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Test smoke state handler",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.SmokeState:build_test_report_data(mock_device, 1, clusters.SmokeCoAlarm.attributes.SmokeState.NORMAL)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.SmokeState:build_test_report_data(mock_device, 1, clusters.SmokeCoAlarm.attributes.SmokeState.WARNING)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.SmokeState:build_test_report_data(mock_device, 1, clusters.SmokeCoAlarm.attributes.SmokeState.CRITICAL)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
    }
  }
)

test.register_message_test(
  "Test CO state handler",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.COState:build_test_report_data(mock_device, 1, clusters.SmokeCoAlarm.attributes.SmokeState.NORMAL)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.COState:build_test_report_data(mock_device, 1, clusters.SmokeCoAlarm.attributes.SmokeState.WARNING)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.detected())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.COState:build_test_report_data(mock_device, 1, clusters.SmokeCoAlarm.attributes.SmokeState.CRITICAL)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.detected())
    }
  }
)

test.register_message_test(
  "Test battery alert handler",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.BatteryAlert:build_test_report_data(mock_device, 1, clusters.SmokeCoAlarm.attributes.BatteryAlert.NORMAL)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.batteryLevel.battery.normal())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.BatteryAlert:build_test_report_data(mock_device, 1, clusters.SmokeCoAlarm.attributes.BatteryAlert.WARNING)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.batteryLevel.battery.warning())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.BatteryAlert:build_test_report_data(mock_device, 1, clusters.SmokeCoAlarm.attributes.BatteryAlert.CRITICAL)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.batteryLevel.battery.critical())
    },
  }
)

test.register_message_test(
  "Test test in progress handler",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.TestInProgress:build_test_report_data(mock_device, 1, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.tested())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.tested())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.TestInProgress:build_test_report_data(mock_device, 1, false)
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {mock_device.id, clusters.SmokeCoAlarm.attributes.SmokeState:read(mock_device)},
    },
    {
      channel = "matter",
      direction = "send",
      message = {mock_device.id, clusters.SmokeCoAlarm.attributes.COState:read(mock_device)}
    }
  }
)

test.register_message_test(
  "Test hardware fault alert handler",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.HardwareFaultAlert:build_test_report_data(mock_device, 1, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.hardwareFault.hardwareFault.detected())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.HardwareFaultAlert:build_test_report_data(mock_device, 1, false)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.hardwareFault.hardwareFault.clear())
    }
  }
)

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
        clusters.RelativeHumidityMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 4049)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 40 }))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RelativeHumidityMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 4050)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 41 }))
    }
  }
)

test.register_message_test(
  "Carbon Monoxide reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.CarbonMonoxideConcentrationMeasurement.server.attributes.MeasurementUnit:build_test_report_data(mock_device, 1, clusters.CarbonMonoxideConcentrationMeasurement.server.attributes.MeasurementUnit.PPM)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.CarbonMonoxideConcentrationMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, SinglePrecisionFloat(0, 6, 0.5625))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.carbonMonoxideMeasurement.carbonMonoxideLevel({value = 100, unit = "ppm"}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.CarbonMonoxideConcentrationMeasurement.server.attributes.MeasurementUnit:build_test_report_data(mock_device, 1, clusters.CarbonMonoxideConcentrationMeasurement.server.attributes.MeasurementUnit.PPB)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.CarbonMonoxideConcentrationMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 1, SinglePrecisionFloat(0, 13, 0.220703125))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.carbonMonoxideMeasurement.carbonMonoxideLevel({value = 10, unit = "ppm"}))
    }
  }
)

test.run_registered_tests()
