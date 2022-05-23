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

local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local Basic = zcl_clusters.Basic
local PowerConfiguration = zcl_clusters.PowerConfiguration
local utils = require "st.utils"

local APPLICATION_VERSION = "application_version"

local ZIGBEE_MOTION_SENSOR_FINGERPRINTS = {
  { mfr = "Third Reality, Inc", model = "3RMS16BZ"},
  { mfr = "THIRDREALITY", model = "3RMS16BZ"}
}

local is_third_reality_motion_sensor = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_MOTION_SENSOR_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local device_added = function(self, device)
  device:set_field(APPLICATION_VERSION, 0)
  device:send(Basic.attributes.ApplicationVersion:read(device))
end

local function application_version_attr_handler(driver, device, value, zb_rx)
  local version = tonumber(value.value)
  device:set_field(APPLICATION_VERSION, version, {persist = true})
end

local function battery_percentage_handler(driver, device, raw_value, zb_rx)
  local softwareVersion = device:get_field(APPLICATION_VERSION)
  local percentage

  if softwareVersion and softwareVersion <= 0x17 then
    -- Version 1.0.23 (23 == 0x17) and earlier incorrectly reports battery percentage
    percentage = utils.clamp_value(raw_value.value, 0, 100)
  else
    percentage = utils.clamp_value(utils.round(raw_value.value / 2), 0, 100)
  end

  device:emit_event(capabilities.battery.battery(percentage))
end

local third_reality_motion_sensor = {
  NAME = "Third reality motion sensor",
  zigbee_handlers = {
    attr = {
      [Basic.ID] = {
        [Basic.attributes.ApplicationVersion.ID] = application_version_attr_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_percentage_handler
      }
    }
  },
  lifecycle_handlers = {
    added = device_added,
  },
  can_handle = is_third_reality_motion_sensor
}

return third_reality_motion_sensor
