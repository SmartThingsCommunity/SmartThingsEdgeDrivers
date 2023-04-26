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

local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement

local devices = {
  ORVIBO_CONTACT = {
    FINGERPRINTS = {
      { mfr = "ORVIBO", model = "e70f96b3773a4c9283c6862dbafb6a99" }
    },
    CONFIGURATION = {
      {
        cluster = IASZone.ID,
        attribute = IASZone.attributes.ZoneStatus.ID,
        minimum_interval = 30,
        maximum_interval = 300,
        data_type = IASZone.attributes.ZoneStatus.base_type,
        reportable_change = 1
      }
    }
  },
  EWELINK_HEIMAN = {
    FINGERPRINTS = {
      { mfr = "eWeLink", model = "DS01" },
      { mfr = "eWeLink", model = "SNZB-04P" },
      { mfr = "HEIMAN", model = "DoorSensor-N" }
    },
    CONFIGURATION = {
      {
        cluster = PowerConfiguration.ID,
        attribute = PowerConfiguration.attributes.BatteryPercentageRemaining.ID,
        minimum_interval = 30,
        maximum_interval = 600,
        data_type = PowerConfiguration.attributes.BatteryPercentageRemaining.base_type,
        reportable_change = 1
      },
      {
        cluster = IASZone.ID,
        attribute = IASZone.attributes.ZoneStatus.ID,
        minimum_interval = 30,
        maximum_interval = 300,
        data_type = IASZone.attributes.ZoneStatus.base_type,
        reportable_change = 1
      }
    }
  },
  THIRD_REALITY_CONTACT = {
    FINGERPRINTS = {
      { mfr = "Third Reality, Inc", model = "3RDS17BZ" }
    },
    CONFIGURATION = {
      {
        cluster = PowerConfiguration.ID,
        attribute = PowerConfiguration.attributes.BatteryPercentageRemaining.ID,
        minimum_interval = 30,
        maximum_interval = 300,
        data_type = PowerConfiguration.attributes.BatteryPercentageRemaining.base_type,
        reportable_change = 1
      }
    }
  },
  CONTACT_TEMPERATURE_SENSOR = {
    FINGERPRINTS = {
      { mfr = "CentraLite", model = "3300-S" },
      { mfr = "CentraLite", model = "3300" },
      { mfr = "CentraLite", model = "3320-L" },
      { mfr = "CentraLite", model = "3323-G" },
      { mfr = "CentraLite", model = "Contact Sensor-A" },
      { mfr = "Visonic", model = "MCT-340 E" },
      { mfr = "Ecolink", model = "4655BC0-R" },
      { mfr = "Ecolink", model = "DWZB1-ECO" },
      { mfr = "iMagic by GreatStar", model = "1116-S" },
      { mfr = "Bosch", model = "RFMS-ZBMS" },
      { mfr = "Megaman", model = "MS601/z1" },
      { mfr = "AduroSmart Eria", model = "CSW_ADUROLIGHT" },
      { mfr = "ADUROLIGHT", model = "CSW_ADUROLIGHT" },
      { mfr = "Sercomm Corp.", model = "SZ-DWS04" },
      { mfr = "DAWON_DNS", model = "SS-B100-ZB" },
      { mfr = "frient A/S", model = "WISZB-120" },
      { mfr = "frient A/S", model = "WISZB-121" },
      { mfr = "Compacta", model = "ZBWDS" }
    },
    CONFIGURATION = {
      {
        cluster = IASZone.ID,
        attribute = IASZone.attributes.ZoneStatus.ID,
        minimum_interval = 30,
        maximum_interval = 300,
        data_type = IASZone.attributes.ZoneStatus.base_type,
        reportable_change = 1
      },
      {
        cluster = TemperatureMeasurement.ID,
        attribute = TemperatureMeasurement.attributes.MeasuredValue.ID,
        minimum_interval = 30,
        maximum_interval = 1800,
        data_type = TemperatureMeasurement.attributes.MeasuredValue.base_type,
        reportable_change = 100
      }
    }
  }
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
