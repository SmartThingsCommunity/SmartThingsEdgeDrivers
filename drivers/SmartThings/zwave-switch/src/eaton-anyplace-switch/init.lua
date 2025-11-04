-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })

local switch_utils = require "switch_utils"

local function basic_set_handler(self, device, cmd)
  if cmd.args.value == 0xFF then
    device:emit_event(capabilities.switch.switch.on())
  else
    device:emit_event(capabilities.switch.switch.off())
  end
end

local function basic_get_handler(self, device, cmd)
  local is_on = device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME)
  device:send(Basic:Report({value = is_on == "on" and 0xff or 0x00}))
end

local function device_added(driver, device)
  switch_utils.emit_event_if_latest_state_missing(device, "main", capabilities.switch, capabilities.switch.switch.NAME, capabilities.switch.switch.off())
end

local function switch_on_handler(driver, device)
  device:emit_event(capabilities.switch.switch.on())
end

local function switch_off_handler(driver, device)
  device:emit_event(capabilities.switch.switch.off())
end

local eaton_anyplace_switch = {
  NAME = "eaton anyplace switch",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = basic_set_handler,
      [Basic.GET] = basic_get_handler
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_handler
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = require("eaton-anyplace-switch.can_handle")
}

return eaton_anyplace_switch
