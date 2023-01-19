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
--- @type st.zwave.CommandClass.Alarm
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 2 })

local FIBARO_DOOR_WINDOW_SENSOR_2_FINGERPRINTS = {
  { manufacturerId = 0x010F, productType = 0x0702, productId = 0x1000 }, -- Fibaro Open/Closed Sensor 2 (FGDW-002) / Europe
  { manufacturerId = 0x010F, productType = 0x0702, productId = 0x2000 }, -- Fibaro Open/Closed Sensor 2 (FGDW-002) / NA
  { manufacturerId = 0x010F, productType = 0x0702, productId = 0x3000 } -- Fibaro Open/Closed Sensor 2 (FGDW-002) / ANZ
}

local function can_handle_fibaro_door_window_sensor_2(opts, driver, device, cmd, ...)
  for _, fingerprint in ipairs(FIBARO_DOOR_WINDOW_SENSOR_2_FINGERPRINTS) do
    if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function device_added(self, device)
  -- device:emit_event(capabilities.tamperAlert.tamper.clear())
  -- device:emit_event(capabilities.contactSensor.contact.open())
  -- device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.cleared())
end

local function alarm_report_handler(self, device, cmd)
  local zwave_alarm_type = cmd.args.z_wave_alarm_type
  local zwave_alarm_event = cmd.args.z_wave_alarm_event
  local event
  if zwave_alarm_type == Alarm.z_wave_alarm_type.ACCESS_CONTROL then
    if zwave_alarm_event == 22 then
      event = capabilities.contactSensor.contact.open()
    elseif zwave_alarm_event == 23 then
      event = capabilities.contactSensor.contact.closed()
    end
  elseif zwave_alarm_type == Alarm.z_wave_alarm_type.BURGLAR then
    if zwave_alarm_event == 0 then
      event = capabilities.tamperAlert.tamper.clear()
    elseif zwave_alarm_event == Alarm.z_wave_alarm_event.burglar.TAMPERING_PRODUCT_COVER_REMOVED then
      event = capabilities.tamperAlert.tamper.detected()
    end
  elseif zwave_alarm_type == Alarm.z_wave_alarm_type.HEAT then
    if zwave_alarm_event == 0 then
      event = capabilities.temperatureAlarm.temperatureAlarm.cleared()
    elseif zwave_alarm_event == Alarm.z_wave_alarm_event.heat.OVERDETECTED then
      event = capabilities.temperatureAlarm.temperatureAlarm.heat()
    elseif zwave_alarm_event == Alarm.z_wave_alarm_event.heat.UNDER_DETECTED then
      event = capabilities.temperatureAlarm.temperatureAlarm.freeze()
    end
  end
  if event ~= nil then device:emit_event(event) end
end

local fibaro_door_window_sensor_2 = {
  NAME = "fibaro door window sensor 2",
  zwave_handlers = {
    [cc.ALARM] = {
      [Alarm.REPORT] = alarm_report_handler
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = can_handle_fibaro_door_window_sensor_2,
}

return fibaro_door_window_sensor_2
