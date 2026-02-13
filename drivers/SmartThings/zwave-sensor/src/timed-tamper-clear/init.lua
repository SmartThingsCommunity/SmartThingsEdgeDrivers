-- Copyright 2023 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 4 })
local capabilities = require "st.capabilities"

local TAMPER_TIMER = "_tamper_timer"
local TAMPER_CLEAR = 10

-- This behavior is from zwave-door-window-sensor.groovy. We've seen this behavior
-- in Ecolink and several other z-wave sensors that do not send tamper clear events
local function handle_tamper_event(driver, device, cmd)
  device:emit_event_for_endpoint(cmd.src_channel, capabilities.tamperAlert.tamper.detected())
  -- device doesn't report all clear
  local tamper_timer = device:get_field(TAMPER_TIMER)
  if tamper_timer ~= nil then
    device.thread:cancel_timer(tamper_timer)
  end
  device:set_field(TAMPER_TIMER, device.thread:call_with_delay(TAMPER_CLEAR, function()
    device:emit_event_for_endpoint(cmd.src_channel, capabilities.tamperAlert.tamper.clear())
    device:set_field(TAMPER_TIMER, nil)
  end))
end

local timed_tamper_clear = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = handle_tamper_event
    }
  },
  NAME = "timed tamper clear",
  can_handle = require("timed-tamper-clear.can_handle"),
}

return timed_tamper_clear
