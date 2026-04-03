-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local data_types = require "st.zigbee.data_types"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local IASWD = zcl_clusters.IASWD
local IASZone = zcl_clusters.IASZone
local IaswdLevel = IASWD.types.IaswdLevel
local SirenConfiguration = IASWD.types.SirenConfiguration
local WarningMode = IASWD.types.WarningMode
local Strobe = IASWD.types.Strobe
local capabilities = require "st.capabilities"
local ALARM_COMMAND = "alarmCommand"
local DEFAULT_MAX_WARNING_DURATION = 1800
local ALARM_STROBE_DUTY_CYCLE = 40

local alarm_command = {
  OFF = 0,
  SIREN = 1,
  STROBE = 2,
  BOTH = 3
}

local function device_added (driver, device)
  device:emit_event(capabilities.switch.switch.off())
  device:emit_event(capabilities.alarm.alarm.off())
  if(device:supports_capability(capabilities.tamperAlert)) then
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  end
  device:send(IASWD.attributes.MaxDuration:read(device))
end

local function do_refresh(driver, device)
  device:refresh()
end

local function do_configure(driver, device)
  device:configure()
end

local function generate_event_from_zone_status(driver, device, zone_status, zb_rx)
  if device:supports_capability(capabilities.tamperAlert) then
    device:emit_event(zone_status:is_tamper_set() and capabilities.tamperAlert.tamper.detected() or capabilities.tamperAlert.tamper.clear())
  end
end

local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  local zone_status = zb_rx.body.zcl_body.zone_status
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function send_siren_command(device, warning_mode, warning_siren_level, warning_duration, strobe_active, strobe_level)
  local siren_configuration

  siren_configuration = SirenConfiguration(0x00)
  siren_configuration:set_warning_mode(warning_mode)
  siren_configuration:set_siren_level(warning_siren_level)
  siren_configuration:set_strobe(strobe_active)

  device:send(
          IASWD.server.commands.StartWarning(
                  device,
                  siren_configuration,
                  data_types.Uint16(warning_duration),
                  data_types.Uint8(ALARM_STROBE_DUTY_CYCLE),
                  data_types.Enum8(strobe_level)
          )
  )
end

local function siren_switch_off_handler(driver, device, command)
  device:set_field(ALARM_COMMAND, alarm_command.OFF, {persist = true})
  send_siren_command(device, WarningMode.STOP, IaswdLevel.LOW_LEVEL, DEFAULT_MAX_WARNING_DURATION, Strobe.NO_STROBE, IaswdLevel.LOW_LEVEL)
end

local function siren_alarm_siren_handler(alarm_cmd, WarningMode, Strobe, strobe_level)
  return function(driver, device, command)
    device:set_field(ALARM_COMMAND, alarm_cmd, {persist = true})

    local sirenVolume_msg = tonumber(device.preferences.sirenVolume)
    local warning_duration = tonumber(device.preferences.warningDuration)

    send_siren_command(device, WarningMode , sirenVolume_msg == nil or IaswdLevel.VERY_HIGH_LEVEL ,warning_duration == nil or DEFAULT_MAX_WARNING_DURATION, Strobe, strobe_level)

    device.thread:call_with_delay(warning_duration, function() -- Send command to switch from siren to off in the app when the siren is done
      if(device:get_field(ALARM_COMMAND) ~= alarm_command.OFF) then
        siren_switch_off_handler(driver, device, alarm_cmd)
      end
    end)
  end
end

local MultiIR_siren_driver = {
  NAME = "MultiIR siren",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
  },
  capability_handlers = {
    [capabilities.alarm.ID] = {
      [capabilities.alarm.commands.off.NAME] = siren_switch_off_handler,
      [capabilities.alarm.commands.siren.NAME] = siren_alarm_siren_handler(alarm_command.SIREN, WarningMode.BURGLAR, Strobe.NO_STROBE, IaswdLevel.LOW_LEVEL),
      [capabilities.alarm.commands.both.NAME] = siren_alarm_siren_handler(alarm_command.BOTH, WarningMode.BURGLAR, Strobe.USE_STROBE , IaswdLevel.VERY_HIGH_LEVEL),
    [capabilities.alarm.commands.strobe.NAME] = siren_alarm_siren_handler(alarm_command.STROBE, WarningMode.STOP,  Strobe.USE_STROBE, IaswdLevel.VERY_HIGH_LEVEL)
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = siren_alarm_siren_handler(alarm_command.BOTH, WarningMode.BURGLAR, Strobe.USE_STROBE , IaswdLevel.VERY_HIGH_LEVEL),
      [capabilities.switch.commands.off.NAME] = siren_switch_off_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zigbee_handlers = {
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    },
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      }
    }
  },
  can_handle = require("MultiIR.can_handle"),
}

return MultiIR_siren_driver