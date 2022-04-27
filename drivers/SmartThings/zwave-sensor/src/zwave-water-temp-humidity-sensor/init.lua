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
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({version=1})
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.SensorBinary
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })

local ZWAVE_WATER_TEMP_HUMIDITY_FINGERPRINTS = {
  { manufacturerId = 0x0371, productType = 0x0002, productId = 0x0013 }, -- Aeotec Water Sensor 7 Pro EU
  { manufacturerId = 0x0371, productType = 0x0102, productId = 0x0013 }, -- Aeotec Water Sensor 7 Pro US
  { manufacturerId = 0x0371, productType = 0x0202, productId = 0x0013 }, -- Aeotec Water Sensor 7 Pro AU
}

--- Determine whether the passed device is zwave water temperature humidiry sensor
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_zwave_water_temp_humidity_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZWAVE_WATER_TEMP_HUMIDITY_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local zwave_handlers = {}

--- Default handler for notification command class reports
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Notification.Report
local function notification_report_handler(self, device, cmd)
  local event
  local water_notification_events_map = {
    [Notification.event.water.LEAK_DETECTED_LOCATION_PROVIDED] = capabilities.waterSensor.water.wet(),
    [Notification.event.water.LEAK_DETECTED] = capabilities.waterSensor.water.wet(),
    [Notification.event.water.STATE_IDLE] = capabilities.waterSensor.water.dry(),
    [Notification.event.water.UNKNOWN_EVENT_STATE] = capabilities.waterSensor.water.dry(),
  }

  if cmd.args.notification_type == Notification.notification_type.WATER then
    event = water_notification_events_map[cmd.args.event]
  end
  if cmd.args.notification_type == Notification.notification_type.HOME_SECURITY then
    if cmd.args.event == Notification.event.home_security.STATE_IDLE then
      event = capabilities.tamperAlert.tamper.clear()
    elseif cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED then
      event = capabilities.tamperAlert.tamper.detected()
      device.thread:call_with_delay(10, function(d)
        device:emit_event(capabilities.tamperAlert.tamper.clear())
      end)
    end
  end
  if (event ~= nil) then device:emit_event(event) end
end

local zwave_water_temp_humidity_sensor = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
  },
  NAME = "zwave water temp humidity sensor",
  can_handle = can_handle_zwave_water_temp_humidity_sensor
}

return zwave_water_temp_humidity_sensor
