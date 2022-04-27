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

local ColorControl = clusters.ColorControl

local devices = {
  IKEA_RGB_BULB = {
    FINGERPRINTS = {
      { mfr = "IKEA of Sweden", model = "TRADFRI bulb E27 CWS opal 600lm" },
      { mfr = "IKEA of Sweden", model = "TRADFRI bulb E26 CWS opal 600lm" }
    },
    CONFIGURATION = {
      {
        cluster = ColorControl.ID,
        attribute = ColorControl.attributes.CurrentX.ID,
        minimum_interval = 1,
        maximum_interval = 3600,
        data_type = ColorControl.attributes.CurrentX.base_type,
        reportable_change = 16
      },
      {
        cluster = ColorControl.ID,
        attribute = ColorControl.attributes.CurrentY.ID,
        minimum_interval = 1,
        maximum_interval = 3600,
        data_type = ColorControl.attributes.CurrentY.base_type,
        reportable_change = 16
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
