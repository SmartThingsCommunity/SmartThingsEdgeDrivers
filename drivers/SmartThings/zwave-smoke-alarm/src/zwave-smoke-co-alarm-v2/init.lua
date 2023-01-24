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
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})

local SMOKE_CO_ALARM_V2_FINGERPRINTS = {
  { manufacturerId = 0x010F, productType = 0x1201, productId = 0x1000 }, -- Fibaro CO Sensor
  { manufacturerId = 0x010F, productType = 0x1201, productId = 0x1001 }  -- Fibaro CO Sensor
}

--- Determine whether the passed device is Smoke Alarm
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @return boolean true if the device is smoke co alarm
local function can_handle_v2_alarm(opts, driver, device, cmd, ...)
  for _, fingerprint in ipairs(SMOKE_CO_ALARM_V2_FINGERPRINTS) do
    if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local device_added = function(self, device)
  -- device:emit_event(capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
  -- device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.cleared())
  -- device:emit_event(capabilities.tamperAlert.tamper.clear())
end

--- Default handler for alarm command class reports
---
--- This converts alarm V2 reports to correct smoke events
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Alarm.Report
local function alarm_report_handler(self, device, cmd)
  local CARBON_MONOXIDE_TEST = 0x03
  local CARBON_MONOXIDE_TEST_CLEAR = ""
  local zwaveAlarmType = cmd.args.z_wave_alarm_type
  local zwaveAlarmEvent = cmd.args.z_wave_alarm_event

  if zwaveAlarmType == Alarm.z_wave_alarm_type.CO then
    if zwaveAlarmEvent == Notification.event.co.STATE_IDLE then
      device:emit_event(capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
    elseif zwaveAlarmEvent == Alarm.z_wave_alarm_event.co.CARBON_MONOXIDE_DETECTED then
      device:emit_event(capabilities.carbonMonoxideDetector.carbonMonoxide.detected())
    elseif zwaveAlarmEvent == CARBON_MONOXIDE_TEST then
      local event_parameter = cmd.args.event_parameter

      if event_parameter == CARBON_MONOXIDE_TEST_CLEAR then
        device:emit_event(capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
      else
        device:emit_event(capabilities.carbonMonoxideDetector.carbonMonoxide.tested())
      end
    end
  elseif zwaveAlarmType == Alarm.z_wave_alarm_type.HEAT then
    if zwaveAlarmEvent == Notification.event.heat.STATE_IDLE then
      device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.cleared())
    elseif zwaveAlarmEvent == Alarm.z_wave_alarm_event.heat.OVERDETECTED then
      device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.heat())
    end
  elseif zwaveAlarmType == Alarm.z_wave_alarm_type.BURGLAR then
    if zwaveAlarmEvent == Notification.event.home_security.STATE_IDLE then
      device:emit_event(capabilities.tamperAlert.tamper.clear())
    elseif zwaveAlarmEvent == Alarm.z_wave_alarm_event.burglar.TAMPERING_PRODUCT_COVER_REMOVED then
      device:emit_event(capabilities.tamperAlert.tamper.detected())
    end
  end
end

local zwave_alarm = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = alarm_report_handler
    }
  },
  NAME = "Z-Wave smoke and CO alarm V2",
  can_handle = can_handle_v2_alarm,
  lifecycle_handlers = {
    added = device_added
  },
  sub_drivers = {
    require("zwave-smoke-co-alarm-v2/fibaro-co-sensor-zw5")
  }
}

return zwave_alarm
