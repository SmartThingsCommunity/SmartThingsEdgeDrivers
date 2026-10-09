-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local cc  = require "st.zwave.CommandClass"
local AlarmDefaults = require "st.zwave.defaults.alarm"
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local Battery = (require "st.zwave.CommandClass.Battery")({version=1})

local BASIC_AND_SWITCH_BINARY_REPORT_STROBE_LIMIT = 33
local BASIC_AND_SWITCH_BINARY_REPORT_SIREN_LIMIT = 66


local function basic_report_handler(driver, device, cmd)
  local value = cmd.args.value
  local event

  if value == 0x00 then
    event = capabilities.alarm.alarm.off()
  elseif value <= BASIC_AND_SWITCH_BINARY_REPORT_STROBE_LIMIT then
    event = capabilities.alarm.alarm.strobe()
  elseif value <= BASIC_AND_SWITCH_BINARY_REPORT_SIREN_LIMIT then
    event = capabilities.alarm.alarm.siren()
  else
    event = capabilities.alarm.alarm.both()
  end

  device:emit_event_for_endpoint(cmd.src_channel, event)
end

-- ICP-5323: Zipato siren sometimes fails to make sound for full duration
-- Those alarms do not end with Siren Notification Report.
-- For those cases we add additional state check after alarm duration to
-- synchronize cloud state with actual device state.
local function siren_on(self, device, command)
  AlarmDefaults.capability_handlers[capabilities.alarm.commands.both](self, device, command)
  local query_device = function()
    device:send(Basic:Get({}))
  end
  local alarm_duration = 63
  device.thread:call_with_delay(3, query_device)
  device.thread:call_with_delay(alarm_duration, query_device)
end

local function device_added(self, device)
  device:send(Basic:Get({}))
  device:send(Battery:Get({}))
end

local zipato_siren = {
  NAME = "zipato-siren",
  can_handle = require("zipato-siren.can_handle"),
  capability_handlers = {
    [capabilities.alarm.ID] = {
      [capabilities.alarm.commands.both.NAME] = siren_on,
      [capabilities.alarm.commands.siren.NAME] = siren_on,
      [capabilities.alarm.commands.strobe.NAME] = siren_on
    }
  },
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.REPORT] = basic_report_handler
    },
  },
  lifecycle_handlers = {
    added = device_added
  }
}

return zipato_siren
