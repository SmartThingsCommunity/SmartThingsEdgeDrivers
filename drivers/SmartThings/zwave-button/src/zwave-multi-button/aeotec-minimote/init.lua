-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })



local function basic_set_handler(self, device, cmd)
  local button = cmd.args.value // 40 + 1
  local event = (button * 40 - cmd.args.value) <= 20 and capabilities.button.button.held or capabilities.button.button.pushed
  device:emit_event_for_endpoint(button, event({state_change = true}))
  device:emit_event(event({state_change = true}))
end

local do_configure = function(self, device)
  device:refresh()
  for buttons = 1,4 do
    device:send(Configuration:Set({parameter_number = 240 + buttons , size = 1, configuration_value = 1}))
    device:send(Configuration:Set({parameter_number = (buttons - 1) * 40, size = 4, configuration_value = 1 << 24 | ((buttons - 1) * 40 + 1) << 16}))
    device:send(Configuration:Set({parameter_number = (buttons - 1) * 40 + 20, size = 4, configuration_value = 1 << 24 | ((buttons - 1) * 40 + 21) << 16}))
  end
end

local aeotec_minimote = {
  NAME = "Aeotec Minimote",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = basic_set_handler
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("zwave-multi-button.aeotec-minimote.can_handle"),
}

return aeotec_minimote
