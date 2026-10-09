-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Alarm
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 1 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })

local consts          = require "lock_utils.constants"
local lock_utils      = require "lock_utils.utils"
local tables          = require "lock_utils.tables"

local METHOD = {
  KEYPAD = "keypad",
  MANUAL = "manual",
  COMMAND = "command",
  AUTO = "auto"
}

--- Default handler for alarm command class reports, these were largely OEM-defined
---
--- This converts alarm V1 reports to correct lock events
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Alarm.Report
local function alarm_report_handler(driver, device, cmd)
  local alarm_type = cmd.args.alarm_type
  local credential_index = cmd.args.alarm_level
  local event
  if (alarm_type == 9 or alarm_type == 17) then
    event = capabilities.lock.lock.unknown()
  elseif (alarm_type == 16 or alarm_type == 19) then
    event = capabilities.lock.lock.unlocked()
    if (credential_index ~= nil) then
      local credential = tables.find_entry(device, "credentials", credential_index)
      local user_id = credential and credential.userIndex or nil
      event.data = { userIndex = user_id, method = METHOD.KEYPAD}
    end
  elseif (alarm_type == 18) then
    event = capabilities.lock.lock.locked()
    if (credential_index ~= nil) then
      local credential = tables.find_entry(device, "credentials", credential_index)
      local user_id = credential and credential.userIndex or nil
      event.data = { userIndex = user_id, method = METHOD.KEYPAD}
    end
  elseif (alarm_type == 21) then
    event = capabilities.lock.lock.locked()
    event.data = {method = (cmd.args.alarm_level == 2) and METHOD.MANUAL or METHOD.KEYPAD}
  elseif (alarm_type == 22) then
    event = capabilities.lock.lock.unlocked()
    event.data = {method = METHOD.MANUAL}
  elseif (alarm_type == 23) then
    event = capabilities.lock.lock.unknown()
    event.data = {method = METHOD.COMMAND}
  elseif (alarm_type == 24) then
    event = capabilities.lock.lock.locked()
    event.data = {method = METHOD.COMMAND}
  elseif (alarm_type == 25) then
    event = capabilities.lock.lock.unlocked()
    event.data = {method = METHOD.COMMAND}
  elseif (alarm_type == 26) then
    event = capabilities.lock.lock.unknown()
    event.data = {method = METHOD.AUTO}
  elseif (alarm_type == 27) then
    event = capabilities.lock.lock.locked()
    event.data = {method = METHOD.AUTO}
  elseif (alarm_type == 32) then
    -- all credentials have been deleted
    tables.delete_all_entries(device, "credentials")
    tables.delete_all_entries(device, "users")
  elseif (alarm_type == 33) then
    -- credential has been deleted
    lock_utils.delete_credential_report_helper(device, credential_index)

  elseif (alarm_type == 13 or alarm_type == 112) then
    -- user code changed/set
    lock_utils.set_credential_report_helper(device, credential_index)

  elseif (alarm_type == 34 or alarm_type == 113) then
    -- duplicate lock code. Log duplicate error
    local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
    if command_in_progress then
      lock_utils.emit_command_result(device, capabilities.lockCredentials,
        command_in_progress, consts.COMMAND_RESULT.DUPLICATE)
      lock_utils.clear_busy_state(device)
    end

  elseif (alarm_type == 130) then
    -- batteries replaced
    if (device:is_cc_supported(cc.BATTERY)) then
      driver:call_with_delay(10, function(d)  device:send(Battery:Get({})) end )
    end
  elseif (alarm_type == 161) then
    -- tamper alarm
    event = capabilities.tamperAlert.tamper.detected()
  elseif (alarm_type == 167) then
    -- low battery
    if (device:is_cc_supported(cc.BATTERY)) then
      driver:call_with_delay(10, function(d)  device:send(Battery:Get({})) end )
    end
  elseif (alarm_type == 168) then
    -- critical battery
    event = capabilities.battery.battery(1)
  elseif (alarm_type == 169) then
    -- battery too low to operate
    event = capabilities.battery.battery(0)
  end

  if (event ~= nil) then
    device:emit_event(event)
  end
end

local zwave_lock = {
  zwave_handlers = {
    [cc.ALARM] = {
      [Alarm.REPORT] = alarm_report_handler
    }
  },
  NAME = "Z-Wave lock alarm V1",
  can_handle = require("zwave-alarm-v1-lock.can_handle")
}

return zwave_lock
