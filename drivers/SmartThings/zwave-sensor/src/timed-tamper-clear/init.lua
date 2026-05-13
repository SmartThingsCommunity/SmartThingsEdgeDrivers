-- Copyright 2023 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 4 })
local capabilities = require "st.capabilities"

local TAMPER_TIMER = "_tamper_timer"
local TAMPER_CLEAR = 10

local excluded_devices = {
  FIBARO_DOOR_WINDOW = {
    mfrs = 0x010F
  },
  AEOTEC_AERQ_8 = {
    mfrs = 0x0371,
    product_ids = 0x0039
  },
  AEOTEC_DOOR_WINDOW_SENSOR_8 = {
    mfrs = 0x0371,
    product_ids = 0x0037
  },
  AEOTEC_WATER_SENSOR_8 = {
    mfrs = 0x0371,
    product_ids = 0x0038
  },
}

local function can_handle_tamper_event(opts, driver, zw_device, cmd, ...)
  -- check only for relevant tamper event first
  if not(opts.dispatcher_class == "ZwaveDispatcher" and
    cmd ~= nil and
    cmd.cmd_class ~= nil and
    cmd.cmd_class == cc.NOTIFICATION and
    cmd.cmd_id == Notification.REPORT and
    cmd.args.notification_type == Notification.notification_type.HOME_SECURITY and
    (cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED or
    cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_MOVED)) then
    return false
  end

  -- check exclusion list: if device matches any entry, skip auto-clear
  for _, excluded_device in pairs(excluded_devices) do
    local mfrs          = excluded_device.mfrs
    local product_types = excluded_device.product_types or nil
    local product_ids   = excluded_device.product_ids   or nil

    if mfrs ~= nil then
      if zw_device:id_match(
          mfrs,
          product_types,
          product_ids
        ) then
        return false
      end
    end
  end

  local subdriver = require("timed-tamper-clear")
  return true, subdriver
end

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
  shared_device_thread_enabled = true,
}

return timed_tamper_clear