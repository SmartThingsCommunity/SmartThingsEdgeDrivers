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
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local IASZone = clusters.IASZone

local AURORA_CONTACT_FINGERPRINTS = {
  { mfr = "Aurora", model = "DoorSensor50AU" }, -- Aurora Smart Door/Window Sensor
  { mfr = "Aurora", model = "WindowSensor51AU" }   -- Aurora Smart Door/Window Sensor
}

local AURORA_CONTACT_CONFIGURATION = {
  {
    cluster = IASZone.ID,
    attribute = IASZone.attributes.ZoneStatus.ID,
    minimum_interval = 30,
    maximum_interval = 300,
    data_type = IASZone.attributes.ZoneStatus.base_type,
    reportable_change = 1
  }
}

local function can_handle_aurora_contact(opts, driver, device, ...)
  for _, fingerprint in ipairs(AURORA_CONTACT_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function device_init(driver, device)
  battery_defaults.use_battery_voltage_handling(device)

  for _, attribute in ipairs(AURORA_CONTACT_CONFIGURATION) do
    device:add_configured_attribute(attribute)
    device:add_monitored_attribute(attribute)
  end
end

local aurora_contact = {
  NAME = "Zigbee Aurora Contact Sensor",
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = can_handle_aurora_contact
}

return aurora_contact
