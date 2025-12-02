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

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
--- @type st.utils

local WAVE_DOOR_WINDOW_SENSOR_FINGERPRINTS = {
  { manufacturerId = 0x0460, prod = 0x0100, productId = 0x0081 }  -- Wave Door/Window sensor
}

--- Determine whether the passed device is Wave Door/Window sensor
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_wave_door_window_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(WAVE_DOOR_WINDOW_SENSOR_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end
end

local function notification_report_handler(driver, device, cmd)
  local notificationType = cmd.args.notification_type
  local event = cmd.args.event
  if cmd.args.notification_type == Notification.notification_type.ACCESS_CONTROL then
    if cmd.args.event == Notification.event.home_security.ACCESS_CONTROL then
      event = cmd.args.notification_status == 0 and capabilities.contactSensor.contact.closed() or capabilities.contactSensor.contact.open()
    elseif notificationType == Notification.notification_type.ACCESS_CONTROL then
        if event == Notification.event.access_control.WINDOW_DOOR_IS_OPEN then
         device:emit_event(capabilities.contactSensor.contact.open())
        elseif event == Notification.event.access_control.WINDOW_DOOR_IS_CLOSED then
         device:emit_event(capabilities.contactSensor.contact.closed())
        end
    end
  end
  if (event ~= nil) then
    device:emit_event(event)
  end
end

local wave_door_window_sensor = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    }
  },
  NAME = "shelly wave door window sensor",
  can_handle = can_handle_wave_door_window_sensor
}

return wave_door_window_sensor