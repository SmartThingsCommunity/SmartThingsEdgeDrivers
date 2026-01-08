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
local lock_utils = require "new_lock_utils"

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
  local event = nil
  local credential_index = nil
  if (cmd.args.alarm_level ~= nil) then
    credential_index = cmd.args.alarm_level
  end
  if (alarm_type == 9 or alarm_type == 17) then
    event = capabilities.lock.lock.unknown()
  elseif (alarm_type == 16 or alarm_type == 19) then
    event = capabilities.lock.lock.unlocked()
    if (code_id ~= nil) then
      local user_id = nil
      local credential = lock_utils.get_credential(device, credential_index)
      if (credential ~= nil) then
        user_id = credential.userIndex
      end
      event.data = { userIndex = user_id, method = METHOD.KEYPAD}
    end
  elseif (alarm_type == 18) then
    event = capabilities.lock.lock.locked()
    if (code_id ~= nil) then
      local user_id = nil
      local credential = lock_utils.get_credential(device, credential_index)
      if (credential ~= nil) then
        user_id = credential.userIndex
      end
      event.data = { userIndex = user_id, method = METHOD.KEYPAD}
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
    -- all credentials have been deleted
    for _, credential in pairs(lock_utils.get_credentials(device)) do
      lock_utils.delete_credential(device, credential.credentialIndex)
    end
    lock_utils.send_events(device)
  elseif (alarm_type == 33) then
    -- credential has been deleted.
    if lock_utils.get_credential(device, credential_index) ~= nil then
      lock_utils.delete_credential(device, credential_index)
      lock_utils.send_events(device)
    end
  elseif (alarm_type == 13 or alarm_type == 112) then
    local command = device:get_field(lock_utils.COMMAND_NAME)
    local active_credential = device:get_field(lock_utils.ACTIVE_CREDENTIAL)
    if command ~= nil and command.name == lock_utils.ADD_CREDENTIAL then
    -- create credential if not already present.
      if lock_utils.get_credential(device, credential_index) == nil then
        lock_utils.add_credential(device,
          active_credential.userIndex,
          active_credential.credentialType,
          credential_index)
        lock_utils.send_events(device)
      end
    elseif command ~= nil and command.name == lock_utils.UPDATE_CREDENTIAL then
      -- update credential
      local credential = lock_utils.get_credential(device, credential_index)
      if credential ~= nil then
        lock_utils.update_credential(device, credential.credentialIndex, credential.userIndex, credential.credentialType)
        lock_utils.send_events(device)
      end
    else
      -- out-of-band update. Don't add if already in table.
      if lock_utils.get_credential(device, credential_index) == nil then
        local new_user_index = lock_utils.get_available_user_index(device)
        if new_user_index ~= nil then
          lock_utils.create_user(device, nil, "guest", new_user_index)
          lock_utils.add_credential(device,
            new_user_index,
            lock_utils.CREDENTIAL_TYPE,
            credential_index)
          lock_utils.send_events(device)
        else
          if command ~= nil and command ~= lock_utils.DELETE_ALL_CREDENTIALS and command ~= lock_utils.DELETE_ALL_USERS then
            lock_utils.clear_busy_state(device, lock_utils.STATUS_RESOURCE_EXHAUSTED)
          end
        end
      end
    end
  elseif (alarm_type == 34 or alarm_type == 113) then
    -- adding credential failed since code already exists.
    -- remove the created user if one got made. There is no associated credential.
    local command = device:get_field(lock_utils.COMMAND_NAME)
    local active_credential = device:get_field(lock_utils.ACTIVE_CREDENTIAL)
    lock_utils.delete_user(device, active_credential.userIndex)
    if command ~= nil and command ~= lock_utils.DELETE_ALL_CREDENTIALS and command ~= lock_utils.DELETE_ALL_USERS then
      lock_utils.clear_busy_state(device, lock_utils.STATUS_DUPLICATE)
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
  can_handle = require("using-new-capabilities.zwave-alarm-v1-lock.can_handle")
}

return zwave_lock
