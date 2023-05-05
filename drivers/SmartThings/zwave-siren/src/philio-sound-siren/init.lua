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

local cc = require "st.zwave.CommandClass"
local capabilities = require "st.capabilities"
local Basic = (require "st.zwave.CommandClass.Basic")({version =1})
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({version=2})
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local preferencesMap = require "preferences"

local PHILIO_SOUND_SIREN = {
  { manufacturerId = 0x013C, productType = 0x0004, productId = 0x000A }
}

local PARAMETER_SOUND = "sound"
local SMOKE = 0
local EMERGENCY = 1
local POLICE = 2
local FIRE = 3
local AMBULANCE = 4
local CHIME = 5
local CHIME_OFF_DELAY = 1
local TAMPER_CLEAR_DELAY = 5
local ALARM_OFF = "off"

local sounds = {
  [AMBULANCE] = {notificationType = Notification.notification_type.EMERGENCY,      event = Notification.event.emergency.CONTACT_MEDICAL_SERVICE},
  [CHIME]     = {notificationType = Notification.notification_type.ACCESS_CONTROL, event = Notification.event.access_control.WINDOW_DOOR_IS_OPEN},
  [EMERGENCY] = {notificationType = Notification.notification_type.HOME_SECURITY,  event = Notification.event.home_security.INTRUSION_LOCATION_PROVIDED},
  [FIRE]      = {notificationType = Notification.notification_type.EMERGENCY,      event = Notification.event.emergency.CONTACT_FIRE_SERVICE},
  [POLICE]    = {notificationType = Notification.notification_type.EMERGENCY,      event = Notification.event.emergency.CONTACT_POLICE},
  [SMOKE]     = {notificationType = Notification.notification_type.SMOKE,          event = Notification.event.smoke.DETECTED_LOCATION_PROVIDED}
}

local function can_handle_philio_sound_siren(opts, driver, device, ...)
  for _, fingerprint in ipairs(PHILIO_SOUND_SIREN) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function device_added(self, device)
  device:refresh()
end

local function sendAlarmChimeCommand(device, soundIdx)
  local sound
  if (soundIdx ~= nil and sounds[soundIdx] ~= nil) then
    sound = sounds[soundIdx]
  else
    sound = sounds[EMERGENCY] -- default sound
  end

  if (sound ~= nil) then
    device:send(Notification:Report({
      notification_type = sound.notificationType,
      event = sound.event
    }))
  end
end

local function handle_alarm_on(self, device)
  local sound = preferencesMap.to_numeric_value(device.preferences[PARAMETER_SOUND])
  sendAlarmChimeCommand(device, sound)
end

local function handle_sound_off(self, device)
  device:send(Basic:Set({value=0x00}))
end

local function chime_off(self, device)
  device:emit_event(capabilities.chime.chime.off())

  -- this comment was taken from a former DTH:
  -- If chime() was called during an alarm event, we need to verify that and reset the alarm,
  -- as the alarm does not properly appear to do that.
  local currentAlarm = device:get_latest_state("main", capabilities.alarm.ID,  capabilities.alarm.alarm.NAME)
  if (currentAlarm ~= nil and currentAlarm ~= ALARM_OFF) then
    local sound = preferencesMap.to_numeric_value(device.preferences[PARAMETER_SOUND])
    sendAlarmChimeCommand(device, sound)
  end
end

local function handle_chime(self, device)
  -- this comment was taken from a former DTH:
  -- Chime is kind of special as the alarm treats it as momentary
  -- and thus sends no updates to us, so we'll send this event and then send an off event soon after.
  device:emit_event(capabilities.chime.chime.chime())
  device.thread:call_with_delay(
    CHIME_OFF_DELAY,
    function(d)
      chime_off(self,device)
    end
  )
  sendAlarmChimeCommand(device, CHIME)
end

local function deactivateTamper(device)
  device:emit_event(capabilities.tamperAlert.tamper.clear())
end

local function activateTamper(device)
  device:emit_event(capabilities.tamperAlert.tamper.detected())
  device.thread:call_with_delay(
    TAMPER_CLEAR_DELAY,
    function(d)
      deactivateTamper(device)
    end
  )
end

local function notification_handler(driver, device, cmd)
  local notification_type = cmd.args.notification_type
  local notification_event = cmd.args.event

  if (notification_type == Notification.notification_type.HOME_SECURITY) then
    if notification_event == Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED then
      activateTamper(device)
    elseif notification_event == Notification.event.home_security.STATE_IDLE then
      deactivateTamper(device)
    end
  end
end

local function sensor_binary_report_handler(driver, device, cmd)
  local value = cmd.args.sensor_value
  local sensorType = cmd.args.sensor_type
  if (value and value == SensorBinary.sensor_value.IDLE) then
    device:emit_event(capabilities.switch.switch.off())
    device:emit_event(capabilities.alarm.alarm.off())
    device:emit_event(capabilities.chime.chime.off())
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  elseif (sensorType == SensorBinary.sensor_type.GENERAL) then
    if value and value == SensorBinary.sensor_value.DETECTED_AN_EVENT then
      device:emit_event(capabilities.alarm.alarm.both())
      device:emit_event(capabilities.switch.switch.on())
    end
  elseif (sensorType == SensorBinary.sensor_type.TAMPER) then
    if value and value == SensorBinary.sensor_value.DETECTED_AN_EVENT then
      device:emit_event(capabilities.tamperAlert.tamper.detected())
    end
  end
end

local philio_sound_siren = {
  NAME = "Philio sound siren",
  can_handle = can_handle_philio_sound_siren,
  lifecycle_handlers = {
    added = device_added
  },
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_handler
    },
    [cc.SENSOR_BINARY] = {
      [SensorBinary.REPORT] = sensor_binary_report_handler
    }
  },
  capability_handlers = {
    [capabilities.alarm.ID] = {
      [capabilities.alarm.commands.siren.NAME]  = handle_alarm_on,
      [capabilities.alarm.commands.strobe.NAME] = handle_alarm_on,
      [capabilities.alarm.commands.both.NAME]   = handle_alarm_on,
      [capabilities.alarm.commands.off.NAME]    = handle_sound_off
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_alarm_on,
      [capabilities.switch.commands.off.NAME] = handle_sound_off
    },
    [capabilities.chime.ID] = {
      [capabilities.chime.commands.chime.NAME] = handle_chime,
      [capabilities.chime.commands.off.NAME] = handle_sound_off
    }
  }
}

return philio_sound_siren
