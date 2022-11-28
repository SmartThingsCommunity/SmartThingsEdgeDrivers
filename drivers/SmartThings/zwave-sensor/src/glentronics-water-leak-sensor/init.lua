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
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })

local GLENTRONICS_WATER_LEAK_SENSOR_FINGERPRINTS = {
  { manufacturerId = 0x0084, productType = 0x0093, productId = 0x0114 } -- glentronics water leak sensor
}

--- Determine whether the passed device is glentronics water leak sensor
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_glentronics_water_leak_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(GLENTRONICS_WATER_LEAK_SENSOR_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function notification_report_handler(self, device, cmd)
  local event
  if cmd.args.notification_type == Notification.notification_type.POWER_MANAGEMENT then
    if cmd.args.event == Notification.event.power_management.AC_MAINS_DISCONNECTED then
      event = capabilities.powerSource.powerSource.battery()
    elseif cmd.args.event == Notification.event.power_management.AC_MAINS_RE_CONNECTED then
      event = capabilities.powerSource.powerSource.mains()
    elseif cmd.args.event == Notification.event.power_management.REPLACE_BATTERY_NOW then
      event = capabilities.battery.battery(1)
    elseif cmd.args.event == Notification.event.power_management.BATTERY_IS_FULLY_CHARGED then
      event = capabilities.battery.battery(100)
    end
  elseif cmd.args.notification_type == Notification.notification_type.SYSTEM then
    if cmd.args.event == Notification.event.system.HARDWARE_FAILURE_MANUFACTURER_PROPRIETARY_FAILURE_CODE_PROVIDED then
      if cmd.args.event_parameter:byte(1) == 0 then
        event = capabilities.waterSensor.water.dry()
      elseif cmd.args.event_parameter:byte(1) == 2 then
        event = capabilities.waterSensor.water.wet()
      end
    end
  end

  if (event ~= nil) then
    device:emit_event(event)
  end
end

local function device_added(driver, device)
  -- device:emit_event(capabilities.battery.battery(100))
  -- device:emit_event(capabilities.waterSensor.water.dry())
  -- device:emit_event(capabilities.powerSource.powerSource.mains())
end

local glentronics_water_leak_sensor = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  NAME = "glentronics water leak sensor",
  can_handle = can_handle_glentronics_water_leak_sensor
}

return glentronics_water_leak_sensor
