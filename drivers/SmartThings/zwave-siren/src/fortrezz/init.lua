-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local cc = require "st.zwave.CommandClass"
local capabilities = require "st.capabilities"
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})


local function set_and_get(value)
  return function (self, device, command)
    device:send(Basic:Set({value=value}))
    device:send(Basic:Get({}))
  end
end

local function basic_report_handler(self, device, cmd)
  local siren_event = capabilities.alarm.alarm.both()
  local switch_event = capabilities.switch.switch.on()
  if cmd.args.value == 0  then
    siren_event = capabilities.alarm.alarm.off()
    switch_event = capabilities.switch.switch.off()
  elseif cmd.args.value <= 33 then
    siren_event = capabilities.alarm.alarm.strobe()
  elseif cmd.args.value <= 66 then
    siren_event = capabilities.alarm.alarm.siren()
  end

  device:emit_event(siren_event)
  device:emit_event(switch_event)
end

local fortrezz_siren = {
  NAME = "fortrezz-siren",
  can_handle = require("fortrezz.can_handle"),
  capability_handlers = {
    [capabilities.alarm.ID] = {
      [capabilities.alarm.commands.siren.NAME] = set_and_get(0x42),
      [capabilities.alarm.commands.strobe.NAME] = set_and_get(0x21),
      [capabilities.alarm.commands.both.NAME] = set_and_get(0xFF),
      [capabilities.alarm.commands.off.NAME] = set_and_get(0x00)
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = set_and_get(0xFF),
      [capabilities.switch.commands.off.NAME] = set_and_get(0x00)
    }
  },
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.REPORT] = basic_report_handler
    }
  }
}

return fortrezz_siren
