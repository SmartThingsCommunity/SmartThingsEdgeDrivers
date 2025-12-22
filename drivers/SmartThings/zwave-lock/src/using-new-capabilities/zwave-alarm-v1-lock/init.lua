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
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Alarm
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 1 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.defaults.lockCodes
local lock_code_defaults = require "st.zwave.defaults.lockCodes"
local json = require "dkjson"

local METHOD = {
  KEYPAD = "keypad",
  MANUAL = "manual",
  COMMAND = "command",
  AUTO = "auto"
}

--- Determine whether the passed command is a V1 alarm command
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @return boolean true if the device is smoke co alarm
local function can_handle_v1_alarm(opts, driver, device, cmd, ...)
  return opts.dispatcher_class == "ZwaveDispatcher" and cmd ~= nil and cmd.version ~= nil and cmd.version == 1
end

--- Default handler for alarm command class reports, these were largely OEM-defined
---
--- This converts alarm V1 reports to correct lock events
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Alarm.Report
local function alarm_report_handler(driver, device, cmd)
  local alarm_type = cmd.args.alarm_type
  local event = nil
  local lock_codes = lock_code_defaults.get_lock_codes(device)
  local code_id = nil
  if (cmd.args.alarm_level ~= nil) then
    code_id = tostring(cmd.args.alarm_level)
  end
  if (alarm_type == 9 or alarm_type == 17) then
    event = capabilities.lock.lock.unknown()
  elseif (alarm_type == 16 or alarm_type == 19) then
    event = capabilities.lock.lock.unlocked()
    if (device:supports_capability(capabilities.lockCodes) and code_id ~= nil) then
      local code_name = lock_code_defaults.get_code_name(device, code_id)
      event.data = {codeId = code_id, codeName = code_name, method = METHOD.KEYPAD}
    end
  elseif (alarm_type == 18) then
    event = capabilities.lock.lock.locked()
    if (device:supports_capability(capabilities.lockCodes) and code_id ~= nil) then
      local code_name = lock_code_defaults.get_code_name(device, code_id)
      event.data = {codeId = code_id, codeName = code_name, method = METHOD.KEYPAD}
    end
  elseif (alarm_type == 21) then
    event = capabilities.lock.lock.locked()
    if (cmd.args.alarm_level == 2) then
      event["data"] = {method = METHOD.MANUAL}
    else
      event["data"] = {method = METHOD.KEYPAD}
    end
  elseif (alarm_type == 22) then
    event = capabilities.lock.lock.unlocked()
    event["data"] = {method = METHOD.MANUAL}
  elseif (alarm_type == 23) then
    event = capabilities.lock.lock.unknown()
    event["data"] = {method = METHOD.COMMAND}
  elseif (alarm_type == 24) then
    event = capabilities.lock.lock.locked()
    event["data"] = {method = METHOD.COMMAND}
  elseif (alarm_type == 25) then
    event = capabilities.lock.lock.unlocked()
    event["data"] = {method = METHOD.COMMAND}
  elseif (alarm_type == 26) then
    event = capabilities.lock.lock.unknown()
    event["data"] = {method = METHOD.AUTO}
  elseif (alarm_type == 27) then
    event = capabilities.lock.lock.locked()
    event["data"] = {method = METHOD.AUTO}
  elseif (alarm_type == 32) then
    -- all user codes deleted
    for code_id, _ in pairs(lock_codes) do
      lock_code_defaults.code_deleted(device, code_id)
    end
    device:emit_event(capabilities.lockCodes.lockCodes(json.encode(lock_code_defaults.get_lock_codes(device)), { visibility = { displayed = false } }))
  elseif (alarm_type == 33) then
    -- user code deleted
    if (code_id ~= nil) then
      lock_code_defaults.clear_code_state(device, code_id)
      if (lock_codes[code_id] ~= nil) then
        lock_code_defaults.code_deleted(device, code_id)
        device:emit_event(capabilities.lockCodes.lockCodes(json.encode(lock_code_defaults.get_lock_codes(device)), { visibility = { displayed = false } }))
      end
    end
  elseif (alarm_type == 13 or alarm_type == 112) then
    -- user code changed/set
    if (code_id ~= nil) then
      local code_name = lock_code_defaults.get_code_name(device, code_id)
      local change_type = lock_code_defaults.get_change_type(device, code_id)
      local code_changed_event = capabilities.lockCodes.codeChanged(code_id .. change_type, { state_change = true })
      code_changed_event["data"] = { codeName = code_name}
      lock_code_defaults.code_set_event(device, code_id, code_name)
      lock_code_defaults.clear_code_state(device, code_id)
      device:emit_event(code_changed_event)
    end
  elseif (alarm_type == 34 or alarm_type == 113) then
    -- duplicate lock code
    if (code_id ~= nil) then
      local code_changed_event = capabilities.lockCodes.codeChanged(code_id .. lock_code_defaults.CHANGE_TYPE.FAILED, { state_change = true })
      lock_code_defaults.clear_code_state(device, code_id)
      device:emit_event(code_changed_event)
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
  can_handle = can_handle_v1_alarm,
}

return zwave_lock
