-- Copyright 2022 SmartThings
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

local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"

local TemperatureMeasurement = clusters.TemperatureMeasurement
local RelativeHumidity = clusters.RelativeHumidity
local PowerConfiguration = clusters.PowerConfiguration

local devices = {
  FRIENT_HUMIDITY_TEMP_SENSOR = {
    FINGERPRINTS = {
      { mfr = "frient A/S", model = "HMSZB-110" },
      { mfr = "frient A/S", model = "HMSZB-120" },
      { mfr = "frient A/S", model = "AQSZB-110" }
    },
    CONFIGURATION = {
      {
        cluster = RelativeHumidity.ID,
        attribute = RelativeHumidity.attributes.MeasuredValue.ID,
        minimum_interval = 60,
        maximum_interval = 3600,
        data_type = RelativeHumidity.attributes.MeasuredValue.base_type,
        reportable_change = 300
      },
      {
        cluster = TemperatureMeasurement.ID,
        attribute = TemperatureMeasurement.attributes.MeasuredValue.ID,
        minimum_interval = 30,
        maximum_interval = 3600,
        data_type = TemperatureMeasurement.attributes.MeasuredValue.base_type,
        reportable_change = 100
      },
      {
        cluster = PowerConfiguration.ID,
        attribute = PowerConfiguration.attributes.BatteryVoltage.ID,
        minimum_interval = 30 ,
        maximum_interval = 21600,
        data_type = PowerConfiguration.attributes.BatteryVoltage.base_type,
        reportable_change = 1
      }
    }
  },
  EWELINK_HUMIDITY_TEMP_SENSOR = {
    FINGERPRINTS = {
      { mfr = "eWeLink", model = "TH01" },
      { mfr = "eWeLink", model = "SNZB-02P" }
    },
    CONFIGURATION = {
      {
        cluster = TemperatureMeasurement.ID,
        attribute = TemperatureMeasurement.attributes.MeasuredValue.ID,
        minimum_interval = 10,
        maximum_interval = 7200,
        data_type = TemperatureMeasurement.attributes.MeasuredValue.base_type,
        reportable_change = 50
      },
      {
        cluster = PowerConfiguration.ID,
        attribute = PowerConfiguration.attributes.BatteryPercentageRemaining.ID,
        minimum_interval = 3600,
        maximum_interval = 7200,
        data_type = PowerConfiguration.attributes.BatteryPercentageRemaining.base_type,
        reportable_change = 16
      },
      {
        cluster = RelativeHumidity.ID,
        attribute = RelativeHumidity.attributes.MeasuredValue.ID,
        minimum_interval = 10,
        maximum_interval = 7200,
        data_type = RelativeHumidity.attributes.MeasuredValue.base_type,
        reportable_change = 300
      }
    }
  },
  SONOFF_HUMIDITY_TEMP_SENSOR = {
    FINGERPRINTS = {
      { mfr = "SONOFF", model = "SNZB-02DR2" }
    },
    CONFIGURATION = {
      {
        cluster = TemperatureMeasurement.ID,
        attribute = TemperatureMeasurement.attributes.MeasuredValue.ID,
        minimum_interval = 10,
        maximum_interval = 7200,
        data_type = TemperatureMeasurement.attributes.MeasuredValue.base_type,
        reportable_change = 50
      },
      {
        cluster = PowerConfiguration.ID,
        attribute = PowerConfiguration.attributes.BatteryPercentageRemaining.ID,
        minimum_interval = 3600,
        maximum_interval = 7200,
        data_type = PowerConfiguration.attributes.BatteryPercentageRemaining.base_type,
        reportable_change = 16
      },
      {
        cluster = RelativeHumidity.ID,
        attribute = RelativeHumidity.attributes.MeasuredValue.ID,
        minimum_interval = 10,
        maximum_interval = 7200,
        data_type = RelativeHumidity.attributes.MeasuredValue.base_type,
        reportable_change = 300
      }
    }
  },
  CENTRALITE_TEMP_SENSOR = {
    FINGERPRINTS = {
      { mfr = "CentraLite", model = "3310-S" },
      { mfr = "CentraLite", model = "3310-G" },
      { mfr = "CentraLite", model = "3310" }
    },
    CONFIGURATION = {
      {
        cluster = 0xFC45,
        attribute = 0x0000,
        minimum_interval = 30,
        maximum_interval = 3600,
        data_type = data_types.Uint16,
        reportable_change = 100,
        mfg_code = 0x104E
      },
      {
        cluster = 0xFC45,
        attribute = 0x0000,
        minimum_interval = 30,
        maximum_interval = 3600,
        data_type = data_types.Uint16,
        reportable_change = 100,
        mfg_code = 0xC2DF
      }
    }
  },
}

local configurations = {}

configurations.get_device_configuration = function(zigbee_device)
  for _, device in pairs(devices) do
    for _, fingerprint in pairs(device.FINGERPRINTS) do
      if zigbee_device:get_manufacturer() == fingerprint.mfr and zigbee_device:get_model() == fingerprint.model then
        return device.CONFIGURATION
      end
    end
  end
  return nil
end

return configurations
