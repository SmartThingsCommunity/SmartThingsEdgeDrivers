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
local cc = require "st.zwave.CommandClass"
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local SoundSwitch = (require "st.zwave.CommandClass.SoundSwitch")({version=1})
local preferencesMap = require "preferences"

local AEOTEC_DOORBELL_SIREN_FINGERPRINTS = {
  { manufacturerId = 0x0371, productType = 0x0003, productId = 0x00A2}, -- Aeotec Doorbell 6 (EU)
  { manufacturerId = 0x0371, productType = 0x0103, productId = 0x00A2}, -- Aeotec Doorbell 6 (US)
  { manufacturerId = 0x0371, productType = 0x0203, productId = 0x00A2}, -- Aeotec Doorbell 6 (AU)
  { manufacturerId = 0x0371, productType = 0x0003, productId = 0x00A4}, -- Aeotec Siren 6 (EU)
  { manufacturerId = 0x0371, productType = 0x0103, productId = 0x00A4}, -- Aeotec Siren 6 (US)
  { manufacturerId = 0x0371, productType = 0x0203, productId = 0x00A4}, -- Aeotec Siren 6 (AU)
}

local COMPONENT_NAME = "componentName"
local TONE = "tone"
local VOLUME = "volume"
local STOP_SIREN = "stopSiren"
local CONFIGURE_SOUND_AND_VOLUME = "configureSoundAndVolume"
local TRIGGER_BUTTON_PAIRING = "triggerButtonPairing"
local TRIGGER_BUTTON_UNPAIRING = "triggerButtonUnpairing"
local BUTTON_PAIRING_MODE = "buttonPairingMode"
local BUTTON_UNPAIRING_MODE = "buttonUnpairingMode"
local ON = 0xFF
local OFF = 0x00
local COMPONENT_TAMPER = "sound2"
local DEFAULT_TAMPER_VOLUME = 5
local DEFAULT_TAMPER_SOUND = 17
local LAST_TRIGGERED_ENDPOINT = "last_triggered_endpoint"
local TAMPER_CLEAR_DELAY = 5
local NUMBER_OF_SOUND_COMPONENTS = 8
local BUTTON_BATTERY_LOW = 5
local BUTTON_BATTERY_NORMAL = 99
local DEVICE_PROFILE_CHANGE_IN_PROGRESS = "device_profile_change_in_progress"
local NEXT_BUTTON_BATTERY_EVENT_DETAILS = "next_button_battery_event_details"

local function can_handle_aeotec_doorbell_siren(opts, driver, device, ...)
  for _, fingerprint in ipairs(AEOTEC_DOORBELL_SIREN_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function querySoundStatus(device)
  for endpoint = 2, NUMBER_OF_SOUND_COMPONENTS do
    device:send_to_component(Basic:Get({}), "sound"..endpoint)
  end
end

local function do_refresh(self, device)
  device:send(Basic:Get({}))
  querySoundStatus(device)
end

local function component_to_endpoint(device, component_id)
  local ep_num = component_id:match("sound(%d)")
  return {ep_num and tonumber(ep_num)}
end

local function endpoint_to_component(device, ep)
  local sound_comp = string.format("sound%d", ep)
  if device.profile.components[sound_comp] ~= nil then
    return sound_comp
  else
    return "main"
  end
end

local function configureSound(device, component, toneId, volumeLevel)
  if (component and toneId and volumeLevel) then
    device:send_to_component(SoundSwitch:ConfigurationSet({default_tone_identifier = toneId, volume = volumeLevel}), component)
  end
end

local function updateButtonBatteryStatus(device, endpoint, statusValue)
  if (endpoint and endpoint >= 3 and endpoint <= 5) then
    device:emit_event_for_endpoint(endpoint, capabilities.battery.battery(statusValue))
  end
end

local function handleButtonBatteryEvent(device, endpoint, statusValue)
  local deviceProfileChangeInProgress = device:get_field(DEVICE_PROFILE_CHANGE_IN_PROGRESS)

  if (deviceProfileChangeInProgress and deviceProfileChangeInProgress == true) then
    device:set_field(NEXT_BUTTON_BATTERY_EVENT_DETAILS, {endpoint = endpoint, batteryStatus = statusValue}, {persist = true})
  else
    updateButtonBatteryStatus(device, endpoint, statusValue)
  end
end

local function stop_siren(device, command, args)
  device:send_to_component(Basic:Set({value = OFF}), "main")
  device:send_to_component(Basic:Get({}), "main")
end

--- Handle preference changes
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param event table
--- @param args
local function info_changed(driver, device, event, args)
  local preferences = preferencesMap.get_device_parameters(device)

  -- check if user stops the siren
  local stopSiren = device.preferences[STOP_SIREN]
  if (args.old_st_store.preferences[STOP_SIREN] ~= stopSiren and stopSiren) then
    stop_siren(device)
  end

  -- check if user triggered sound and volume configuration
  local configureSoundAndVolume = device.preferences[CONFIGURE_SOUND_AND_VOLUME]
  if (args.old_st_store.preferences[CONFIGURE_SOUND_AND_VOLUME] ~= configureSoundAndVolume and configureSoundAndVolume) then
    local component = device.preferences[COMPONENT_NAME]
    local toneId = device.preferences[TONE]
    local volumeLevel = device.preferences[VOLUME]
    configureSound(device, component, toneId, volumeLevel)
  end

  -- check if user triggered button unpairing
  local triggerButtonUnpairing = device.preferences[TRIGGER_BUTTON_UNPAIRING]
  if (args.old_st_store.preferences[TRIGGER_BUTTON_UNPAIRING] ~= triggerButtonUnpairing and triggerButtonUnpairing) then
    local buttonUnpairingMode = device.preferences[BUTTON_UNPAIRING_MODE]
    device:send(Configuration:Set(
      {
        parameter_number = preferences[BUTTON_UNPAIRING_MODE].parameter_number,
        size = preferences[BUTTON_UNPAIRING_MODE].size,
        configuration_value = buttonUnpairingMode
      }
    ))
  end

  -- check if user triggered button pairing
  local triggerButtonPairing = device.preferences[TRIGGER_BUTTON_PAIRING]
  if (args.old_st_store.preferences[TRIGGER_BUTTON_PAIRING] ~= triggerButtonPairing and triggerButtonPairing) then
    local buttonPairingMode = device.preferences[BUTTON_PAIRING_MODE]
    device:send(Configuration:Set(
      {
        parameter_number = preferences[BUTTON_PAIRING_MODE].parameter_number,
        size = preferences[BUTTON_PAIRING_MODE].size,
        configuration_value = buttonPairingMode
      }
    ))
  end

  local oldDeviceProfileId = args.old_st_store.profile.id
  local currentDeviceProfileId = device.profile.id

  if (oldDeviceProfileId and currentDeviceProfileId and
      oldDeviceProfileId ~= currentDeviceProfileId and
      device:supports_capability_by_id(capabilities.battery.ID)
  ) then
    device:set_field(DEVICE_PROFILE_CHANGE_IN_PROGRESS, nil, { persist = true})
    local nextButtonBatteryEventDetails = device:get_field(NEXT_BUTTON_BATTERY_EVENT_DETAILS)

    if (nextButtonBatteryEventDetails) then
      updateButtonBatteryStatus(device, nextButtonBatteryEventDetails.endpoint, nextButtonBatteryEventDetails.batteryStatus)
      device:set_field(NEXT_BUTTON_BATTERY_EVENT_DETAILS, nil, {persist = true})
    end
  end
end

local function clearAlarmAndChime(device, endpoint)
  if (endpoint) then
    device:emit_event_for_endpoint(endpoint, capabilities.alarm.alarm.off())
    device:emit_event_for_endpoint(endpoint, capabilities.chime.chime.off())
  end
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

local function clearAlarmAndChimeStateOfSoundComponents(device)
  for endpoint = 1, NUMBER_OF_SOUND_COMPONENTS do
    clearAlarmAndChime(device, endpoint)
  end
end

local function device_added(self, device)
  -- deactivateTamper(device)
  -- clearAlarmAndChimeStateOfSoundComponents(device)
end

local function device_init(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local function activateSoundComponent(device, endpoint)
  if (endpoint) then
    device:emit_event_for_endpoint(endpoint, capabilities.alarm.alarm.both())
    device:emit_event_for_endpoint(endpoint, capabilities.chime.chime.chime())
  end
end

local function changeDeviceProfileIfNeeded(device, endpoint)
  local component = endpoint_to_component(device, endpoint)
  local buttonIsOnboard = device:supports_capability_by_id(capabilities.battery.ID, component)

  if (buttonIsOnboard == false) then
    local new_profile = "aeotec-doorbell-siren-battery"
    device:try_update_metadata({profile = new_profile})
    device:set_field(DEVICE_PROFILE_CHANGE_IN_PROGRESS, true, { persist = true})
  end
end

local function setActiveEndpoint(device, endpoint)
  if (endpoint) then
    device:set_field(LAST_TRIGGERED_ENDPOINT, endpoint, {persist = true})
    activateSoundComponent(device, endpoint)
  end
end

local function setInactiveEndpoint(device)
  local lastTriggeredEndpoint = device:get_field(LAST_TRIGGERED_ENDPOINT)
  if (lastTriggeredEndpoint) then
    clearAlarmAndChime(device, lastTriggeredEndpoint)
    device:set_field(LAST_TRIGGERED_ENDPOINT, nil, {persist = true})
  end
end

local function resetActiveEndpoint(device)
  local lastTriggeredEndpoint = device:get_field(LAST_TRIGGERED_ENDPOINT)
  if (lastTriggeredEndpoint) then
    clearAlarmAndChime(device, lastTriggeredEndpoint)
    device:send_to_component(Basic:Set({value = OFF}), endpoint_to_component(device,lastTriggeredEndpoint))
  end
end

local function do_configure (self, device)
  configureSound(device, COMPONENT_TAMPER, DEFAULT_TAMPER_SOUND, DEFAULT_TAMPER_VOLUME)
end

local function basic_report_handler(self, device, cmd)
  -- device sends basic report (OFF) right after sound (endpoint) is switched ON and handling such events make impossible to stop the endpoint
  -- additionally device sends NotificationReports (SIREN: ACTIVE/STATE_IDLE is sent) and that's main indicator for alarm/chime events
  -- because NotificationReports SIREN/STATE_IDLE is sent when endpoint stops playing
  -- we need to handle this here and do nothing, because z-wave defaults base on BasicReport too and produce alarm and chime events
end

local function notification_report_handler(self, device, cmd)
  local notification_type = cmd.args.notification_type
  local notification_event = cmd.args.event

  if (notification_type == Notification.notification_type.HOME_SECURITY) then
    if (notification_event == Notification.event.home_security.TAMPERING_PRODUCT_MOVED) then
      activateTamper(device)
    elseif (notification_event ==  Notification.event.home_security.STATE_IDLE) then
      deactivateTamper(device)
    end
  elseif (notification_type == Notification.notification_type.SIREN) then
    if (notification_event ==  Notification.event.siren.ACTIVE) then
      setActiveEndpoint(device, cmd.src_channel)
    elseif (notification_event ==  Notification.event.siren.STATE_IDLE) then
      setInactiveEndpoint(device)
    end
  elseif (notification_type == Notification.notification_type.POWER_MANAGEMENT) then
    if (notification_event ==  Notification.event.power_management.REPLACE_BATTERY_SOON) then
      changeDeviceProfileIfNeeded(device, cmd.src_channel)
      handleButtonBatteryEvent(device, cmd.src_channel, BUTTON_BATTERY_LOW)
    elseif (notification_event ==  Notification.event.power_management.STATE_IDLE) then
      changeDeviceProfileIfNeeded(device, cmd.src_channel)
      handleButtonBatteryEvent(device, cmd.src_channel, BUTTON_BATTERY_NORMAL)
    end
  end
end

local function alarmChimeOnOff(device, command, newValue)
  if (device and command and newValue) then
    local endpoint = component_to_endpoint(device, command.component)
    device:send(Basic:Set({value = newValue})):to_endpoint(endpoint)
    if (newValue == ON) then
      setActiveEndpoint(endpoint)
    end
  end
end

local function alarm_chime_on(device, command)
  resetActiveEndpoint(device)
  alarmChimeOnOff(device, command, ON)
end

local function alarm_chime_off(device, command)
  alarmChimeOnOff(device, command, OFF)
end

local aeotec_doorbell_siren = {
  NAME = "aeotec-doorbell-siren",
  can_handle = can_handle_aeotec_doorbell_siren,

  lifecycle_handlers = {
    added = device_added,
    init = device_init,
    doConfigure = do_configure,
    infoChanged = info_changed
  },
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.REPORT] = basic_report_handler
    },
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    }
  },
  capabilities_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [capabilities.alarm.ID] = {
      [capabilities.alarm.commands.both.NAME] = alarm_chime_on,
      [capabilities.alarm.commands.siren.NAME] = alarm_chime_on,
      [capabilities.alarm.commands.strobe.NAME] = alarm_chime_on,
      [capabilities.alarm.commands.off.NAME] = alarm_chime_off
    },
    [capabilities.chime.ID] = {
      [capabilities.chime.commands.chime.NAME] = alarm_chime_on,
      [capabilities.chime.commands.off.NAME] = alarm_chime_off
    }
  }
}

return aeotec_doorbell_siren
