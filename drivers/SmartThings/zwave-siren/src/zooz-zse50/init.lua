-- Copyright 2026 SmartThings
-- Licensed under the Apache License, Version 2.0

local preferencesMap = require "preferences"

local log = require "log"
local st_utils = require "st.utils"
local capabilities = require "st.capabilities"
local defaults = require "st.zwave.defaults"

local cc = require "st.zwave.CommandClass"
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 8 })
local SoundSwitch = (require "st.zwave.CommandClass.SoundSwitch")({ version = 1 })
local Version = (require "st.zwave.CommandClass.Version")({ version = 1 })

--- @param self st.zwave.Driver
--- @param device st.zwave.Device
local function update_firmwareUpdate_capability(self, device, component, major, minor)
  if device:supports_capability_by_id(capabilities.firmwareUpdate.ID, component.id) then
    local fmtFirmwareVersion = string.format("%d.%02d", major, minor)
    device:emit_component_event(component, capabilities.firmwareUpdate.currentVersion({ value = fmtFirmwareVersion }))
  end
end

--- Update the built in capability firmwareUpdate's currentVersion attribute with the
--- Zwave version information received during pairing of the device.
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
local function updateFirmwareVersion(self, device)
  local fw_major = (((device.st_store or {}).zwave_version or {}).firmware or {}).major
  local fw_minor = (((device.st_store or {}).zwave_version or {}).firmware or {}).minor
  if fw_major and fw_minor then
    update_firmwareUpdate_capability(self, device, device.profile.components.main, fw_major, fw_minor)
  else
    device.log.warn("Firmware major or minor version not available.")
  end
end

local function getModeName(toneId, toneInfo)
  return string.format("%s: %s (%ss)", toneId, toneInfo.name, toneInfo.duration)
end

local function playTone(device, tone_id)
  local tones_list = device:get_field("TONES_LIST")
  local default_tone = device:get_field("TONE_DEFAULT") or 1
  local playbackMode = tonumber(device.preferences.playbackMode)
  local duration = 0

  if playbackMode == 1 then
    duration = device.preferences.playbackDuration
  elseif playbackMode == 2 then
    duration = duration * device.preferences.playbackLoop
  elseif tones_list ~= nil and tone_id > 0 then
    if tone_id == 0xFF then
      duration = tones_list[tonumber(default_tone)].duration
    else
      duration = tones_list[tonumber(tone_id)].duration
    end
  end

  log.info(string.format("Playing Tone: %s, playbackMode %s, duration %ss", tone_id, playbackMode, duration))

  device:send(SoundSwitch:TonePlaySet({ tone_identifier = tone_id }))
  device:send(SoundSwitch:TonePlayGet({}))

  local soundSwitch_refresh = function()
    local chime = device:get_latest_state("main", capabilities.chime.ID, capabilities.chime.chime.NAME)
    local mode = device:get_latest_state("main", capabilities.mode.ID, capabilities.mode.mode.NAME)
    log.info(string.format("Running SoundSwitch Refresh: %s | %s", chime, mode))
    if chime ~= "off" or mode ~= "Off" then
      device:send(SoundSwitch:TonePlayGet({}))
    end
  end

  if tone_id > 0 and playbackMode <= 2 then
    local minDuration = math.max(duration, 4)
    device.thread:call_with_delay(minDuration + 0.5, soundSwitch_refresh)
    device.thread:call_with_delay(minDuration + 4, soundSwitch_refresh)
  end

end

local function rebuildTones(device)
  device:emit_event(capabilities.mode.mode("Rebuild List"))
  device:send(SoundSwitch:TonesNumberGet({}))
end

local function refresh_handler(self, device)
  device:default_refresh()
  device:send(Version:Get({}))
  device:send(Notification:Get({
    notification_type = Notification.notification_type.POWER_MANAGEMENT,
    event = Notification.event.power_management.STATE_IDLE,
    v1_alarm_type = 0
  }))
  device:send(SoundSwitch:ConfigurationGet({}))
  device:send(SoundSwitch:TonePlayGet({}))
end

local function setMode_handler(self, device, command)
  local mode_value = command.args.mode
  local mode_split = string.find(mode_value, ":")

  if mode_split ~= nil then
    mode_value = string.sub(mode_value, 1, mode_split - 1)
  end
  log.info(string.format("Command: setMode (%s)", mode_value))

  if mode_value == 'Rebuild List' then
    rebuildTones(device)
  elseif mode_value == 'Off' then
    playTone(device, 0x00)
  else
    playTone(device, tonumber(mode_value))
  end
end

local function setVolume_handler(self, device, cmd)
  local new_volume = st_utils.clamp_value(cmd.args.volume, 0, 100)
  device:send(SoundSwitch:ConfigurationSet({ volume = new_volume }))
end

local function volumeUp_handler(self, device, cmd)
  local volume = device:get_latest_state("main", capabilities.audioVolume.ID, capabilities.audioVolume.volume.NAME) or 50
  volume = st_utils.clamp_value(volume + 2, 0, 100)
  device:send(SoundSwitch:ConfigurationSet({ volume = volume }))
end

local function volumeDown_handler(self, device, cmd)
  local volume = device:get_latest_state("main", capabilities.audioVolume.ID, capabilities.audioVolume.volume.NAME) or 50
  volume = st_utils.clamp_value(volume - 2, 0, 100)
  device:send(SoundSwitch:ConfigurationSet({ volume = volume }))
end

local function tone_on(self, device)
  playTone(device, 0xFF)
end

local function tone_off(self, device)
  playTone(device, 0x00)
end

local function tones_number_report_handler(self, device, cmd)
  local total_tones = cmd.args.supported_tones

  --Max 50 tones per Zooz settings
  if total_tones > 50 then
    total_tones = 50
  end

  local tones_list = { }
  device:set_field("TOTAL_TONES", total_tones)
  device:set_field("TONES_LIST_TMP", tones_list)

  --Get info on all tones
  for tone = 1, total_tones do
    device:send(SoundSwitch:ToneInfoGet({ tone_identifier = tone }))
  end
end

local function tone_info_report_handler(self, device, cmd)
  local tone_id = tonumber(cmd.args.tone_identifier)
  local tone_name = cmd.args.name
  local duration = cmd.args.tone_duration
  local total_tones = device:get_field("TOTAL_TONES")
  local tones_list = device:get_field("TONES_LIST_TMP") or {}

  tones_list[tone_id] = { name = tone_name, duration = duration }
  device:set_field("TONES_LIST_TMP", tones_list)

  if tone_id >= total_tones or #tones_list >= total_tones then
    log.info(string.format("Received info on all tones: tone_id %s, #tones_list %s, total_tones %s", tone_id, #tones_list, total_tones))

    local tones_arguments = { "Off" }
    for il, vl in ipairs(tones_list) do
      table.insert(tones_arguments, getModeName(il, vl))
    end

    device:set_field("TONES_LIST", tones_list, { persist = true })
    device:emit_event(capabilities.mode.supportedModes({ "Rebuild List", table.unpack(tones_arguments) }))
    device:emit_event(capabilities.mode.supportedArguments(tones_arguments))
    device:send(SoundSwitch:TonePlayGet({}))
  end
end

--- Handle when tone is played (TONE_PLAY_REPORT or BASIC_REPORT)
local function tone_playing(self, device, tone_id)
  local tones_list = device:get_field("TONES_LIST")

  if tones_list == nil or tones_list == {} then
    rebuildTones(device)
  end

  if tone_id == 0 then
    device:emit_event(capabilities.alarm.alarm.off())
    device:emit_event(capabilities.chime.chime.off())
    device:emit_event(capabilities.mode.mode("Off"))
  else
    local toneInfo = (tones_list or {})[tone_id] or { name = "Unknown", duration = "0" }
    local modeName = getModeName(tone_id, toneInfo)
    device:emit_event(capabilities.alarm.alarm.both())
    device:emit_event(capabilities.chime.chime.chime())
    device:emit_event(capabilities.mode.mode(modeName))
  end
end

local function tone_play_report_handler(self, device, cmd)
  local tone_id = tonumber(cmd.args.tone_identifier)
  tone_playing(self, device, tone_id)
end

local function basic_report_handler(self, device, cmd)
  local tone_id = tonumber(cmd.args.value)
  tone_playing(self, device, tone_id)
end

--- Handle SoundSwitch Config Reports (volume)
local function soundSwitch_configuration_report(self, device, cmd)
  local volume = st_utils.clamp_value(cmd.args.volume, 0, 100)
  local default_tone = cmd.args.default_tone_identifer
  device:emit_event(capabilities.audioVolume.volume(volume))
  device:set_field("TONE_DEFAULT", default_tone, { persist = true })
end

--- Handle power source changes
local function notification_report_handler(self, device, cmd)
  if cmd.args.notification_type == Notification.notification_type.POWER_MANAGEMENT then
    local event = cmd.args.event
    local powerManagement = Notification.event.power_management

    if event == powerManagement.AC_MAINS_DISCONNECTED then
      device:emit_event(capabilities.powerSource.powerSource.battery())
    elseif event == powerManagement.AC_MAINS_RE_CONNECTED or event == powerManagement.STATE_IDLE then
      device:emit_event(capabilities.powerSource.powerSource.mains())
    end
  end
end

--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Version.Report
local function version_report_handler(driver, device, cmd)
  local major = cmd.args.application_version
  local minor = cmd.args.application_sub_version

  -- Update the built in firmware capability, if available
  update_firmwareUpdate_capability(driver, device, device.profile.components.main, major, minor)
end

--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
local function device_init(driver, device)
  if (device:get_field("TONES_LIST") == nil or device:get_field("TONE_DEFAULT") == nil) then
    rebuildTones(device)
  end
end

--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
local function device_added(driver, device)
  device:send(SoundSwitch:ConfigurationSet({ volume = 10 }))
  updateFirmwareVersion(driver, device)
  device:refresh()
end

--- Handle preference changes (same as default but added hack for unsigned parameters)
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param event table
--- @param args
local function info_changed(driver, device, event, args)
  local preferences = preferencesMap.get_device_parameters(device)

  if preferences then
    local did_configuration_change = false
    for id, value in pairs(device.preferences) do
      if args.old_st_store.preferences[id] ~= value and preferences[id] then
        local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
        --Hack to convert to signed integer
        local size_factor = math.floor(256 ^ preferences[id].size)
        if new_parameter_value >= (size_factor / 2) then
          new_parameter_value = new_parameter_value - size_factor
        end
        --END Hack
        device:send(Configuration:Set({ parameter_number = preferences[id].parameter_number, size = preferences[id].size, configuration_value = new_parameter_value }))
        did_configuration_change = true
      end
    end

    if did_configuration_change then
      local delayed_command = function()
        device:send(Basic:Set({ value = 0x00 }))
      end
      device.thread:call_with_delay(1, delayed_command)
    end

  end
end

local zooz_zse50 = {
  NAME = "Zooz ZSE50",
  can_handle = require("zooz-zse50.can_handle"),

  supported_capabilities = {
    capabilities.battery,
    capabilities.chime,
    capabilities.mode,
    capabilities.audioVolume,
    capabilities.powerSource,
    capabilities.firmwareUpdate,
    capabilities.configuration,
    capabilities.refresh
  },

  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.REPORT] = basic_report_handler
    },
    [cc.SOUND_SWITCH] = {
      [SoundSwitch.TONES_NUMBER_REPORT] = tones_number_report_handler,
      [SoundSwitch.TONE_INFO_REPORT] = tone_info_report_handler,
      [SoundSwitch.TONE_PLAY_REPORT] = tone_play_report_handler,
      [SoundSwitch.CONFIGURATION_REPORT] = soundSwitch_configuration_report
    },
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
    [cc.VERSION] = {
      [Version.REPORT] = version_report_handler
    }
  },

  capability_handlers = {
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = setMode_handler
    },
    [capabilities.audioVolume.ID] = {
      [capabilities.audioVolume.commands.setVolume.NAME] = setVolume_handler,
      [capabilities.audioVolume.commands.volumeUp.NAME] = volumeUp_handler,
      [capabilities.audioVolume.commands.volumeDown.NAME] = volumeDown_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler
    },
    [capabilities.alarm.ID] = {
      [capabilities.alarm.commands.both.NAME] = tone_on,
      [capabilities.alarm.commands.off.NAME] = tone_off
    },
    [capabilities.chime.ID] = {
      [capabilities.chime.commands.chime.NAME] = tone_on,
      [capabilities.chime.commands.off.NAME] = tone_off
    },

  },

  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = info_changed
  }
}

defaults.register_for_default_handlers(zooz_zse50, zooz_zse50.supported_capabilities)

return zooz_zse50
