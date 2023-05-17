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
local cc = require "st.zwave.CommandClass"

local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local UserCode = (require "st.zwave.CommandClass.UserCode")({version=1})
local access_control_event = Notification.event.access_control

local json = require "dkjson"
local constants = require "st.zwave.constants"

local LockDefaults = require "st.zwave.defaults.lock"
local LockCodesDefaults = require "st.zwave.defaults.lockCodes"
local get_lock_codes = LockCodesDefaults.get_lock_codes
local clear_code_state = LockCodesDefaults.clear_code_state
local code_deleted = LockCodesDefaults.code_deleted

local SAMSUNG_MFR = 0x022E

local function can_handle_samsung_lock(opts, self, device, cmd, ...)
  return device.zwave_manufacturer_id == SAMSUNG_MFR
end

local function get_ongoing_code_set(device)
  local code_id
  local code_state = device:get_field(constants.CODE_STATE)
  if code_state ~= nil then
    for key, state in pairs(code_state) do
      if state ~= nil then
        code_id = key:match("setName(%d)")
      end
    end
  end
  return code_id
end

local function notification_report_handler(self, device, cmd)
  local event
  if (cmd.args.notification_type == Notification.notification_type.ACCESS_CONTROL) then
    local event_code = cmd.args.event
    if event_code == access_control_event.AUTO_LOCK_NOT_FULLY_LOCKED_OPERATION then
      event = capabilities.lock.lock.unlocked()
    elseif event_code == access_control_event.NEW_USER_CODE_ADDED then
      local code_id = get_ongoing_code_set(device)
      if code_id ~= nil then
        device:send(UserCode:Get({user_identifier = code_id}))
        return
      end
    elseif event_code == access_control_event.NEW_USER_CODE_NOT_ADDED_DUE_TO_DUPLICATE_CODE then
      local code_id = get_ongoing_code_set(device)
      if code_id ~= nil then
        event = capabilities.lockCodes.codeChanged(code_id .. " failed", { state_change = true })
        clear_code_state(device, code_id)
      end
    elseif event_code == access_control_event.NEW_PROGRAM_CODE_ENTERED_UNIQUE_CODE_FOR_LOCK_CONFIGURATION then
      -- Update Master Code in the same way as in defaults...
      LockCodesDefaults.zwave_handlers[cc.NOTIFICATION][Notification.REPORT](self, device, cmd)
      -- ...and delete rest of them, as lock does
      local lock_codes = get_lock_codes(device)
      for code_id, _ in pairs(lock_codes) do
        if code_id ~= "0" then
          code_deleted(device, code_id)
        end
      end
      event = capabilities.lockCodes.lockCodes(json.encode(get_lock_codes(device)), { visibility = { displayed = false } })
    end
  end

  if event ~= nil then
    device:emit_event(event)
  else
    LockDefaults.zwave_handlers[cc.NOTIFICATION][Notification.REPORT](self, device, cmd)
    LockCodesDefaults.zwave_handlers[cc.NOTIFICATION][Notification.REPORT](self, device, cmd)
  end
end

-- Used doConfigure instead of added to not overwrite parent driver's added_handler
local function do_configure(self, device)
  -- taken directly from DTH
  -- Samsung locks won't allow you to enter the pairing menu when locked, so it must be unlocked
  device:emit_event(capabilities.lock.lock.unlocked())
  device:emit_event(capabilities.lockCodes.lockCodes(json.encode({["0"] = "Master Code"} ), { visibility = { displayed = false } }))
end

local samsung_lock = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  NAME = "Samsung Lock",
  can_handle = can_handle_samsung_lock,
}

return samsung_lock
