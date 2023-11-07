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
local constants = require "st.zwave.constants"
local json = require "dkjson"

local UserCode = (require "st.zwave.CommandClass.UserCode")({version=1})
local user_id_status = UserCode.user_id_status
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local access_control_event = Notification.event.access_control
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=2})
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local Association = (require "st.zwave.CommandClass.Association")({version=1})

local LockCodesDefaults = require "st.zwave.defaults.lockCodes"

local SCHLAGE_MFR = 0x003B
local SCHLAGE_LOCK_CODE_LENGTH_PARAM = {number = 16, size = 1}

local DEFAULT_COMMANDS_DELAY = 4.2 -- seconds

local function can_handle_schlage_lock(opts, self, device, cmd, ...)
  return device.zwave_manufacturer_id == SCHLAGE_MFR
end

local function set_code_length(self, device, cmd)
  local length = cmd.args.length
  if length >= 4 and length <= 8 then
    device:send(Configuration:Set({
      parameter_number = SCHLAGE_LOCK_CODE_LENGTH_PARAM.number,
      configuration_value = length,
      size = SCHLAGE_LOCK_CODE_LENGTH_PARAM.size
    }))
  end
end

local function reload_all_codes(self, device, cmd)
  LockCodesDefaults.capability_handlers[capabilities.lockCodes.commands.reloadAllCodes](self, device, cmd)
  local current_code_length = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.codeLength.NAME)
  if current_code_length == nil then
    device:send(Configuration:Get({parameter_number = SCHLAGE_LOCK_CODE_LENGTH_PARAM.number}))
  end
end

local function set_code(self, device, cmd)
  if (cmd.args.codePIN == "") then
    self:inject_capability_command(device, {
      capability = capabilities.lockCodes.ID,
      command = capabilities.lockCodes.commands.nameSlot.NAME,
      args = {cmd.args.codeSlot, cmd.args.codeName},
    })
  else
    -- copied from defaults with additional check for Schlage's configuration
    if (cmd.args.codeName ~= nil and cmd.args.codeName ~= "") then
      if (device:get_field(constants.CODE_STATE) == nil) then device:set_field(constants.CODE_STATE, { persist = true }) end
      local code_state = device:get_field(constants.CODE_STATE)
      code_state["setName"..cmd.args.codeSlot] = cmd.args.codeName
      device:set_field(constants.CODE_STATE, code_state, { persist = true })
    end
    local send_set_user_code = function ()
      device:send(UserCode:Set({
        user_identifier = cmd.args.codeSlot,
        user_code = cmd.args.codePIN,
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS})
      )
    end
    local current_code_length = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.codeLength.NAME)
    if current_code_length == nil then
      device:send(Configuration:Get({parameter_number = SCHLAGE_LOCK_CODE_LENGTH_PARAM.number}))
      device.thread:call_with_delay(DEFAULT_COMMANDS_DELAY, send_set_user_code)
    else
      send_set_user_code()
    end
  end
end

local function do_configure(self, device)
  device:send(Configuration:Get({parameter_number = SCHLAGE_LOCK_CODE_LENGTH_PARAM.number}))
  device:send(Association:Set({grouping_identifier = 2, node_ids = {self.environment_info.hub_zwave_id}}))
end

local function basic_set_handler(self, device, cmd)
  device:emit_event(cmd.args.value == 0 and capabilities.lock.lock.unlocked() or capabilities.lock.lock.locked())
  device:send(Association:Remove({grouping_identifier = 1, node_ids = {self.environment_info.hub_zwave_id}}))
end

local function configuration_report(self, device, cmd)
  local parameter_number = cmd.args.parameter_number
  if parameter_number == SCHLAGE_LOCK_CODE_LENGTH_PARAM.number then
    local reported_code_length = cmd.args.configuration_value
    local current_code_length = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.codeLength.NAME)
    if current_code_length ~= nil and current_code_length ~= reported_code_length then
      local all_codes_deleted_mocked_command = Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = access_control_event.ALL_USER_CODES_DELETED
      })
      LockCodesDefaults.zwave_handlers[cc.NOTIFICATION][Notification.REPORT](self, device, all_codes_deleted_mocked_command)
    end
    device:emit_event(capabilities.lockCodes.codeLength(reported_code_length))
  end
end

local function is_user_code_report_mfr_specific(device, cmd)
  local reported_user_id_status = cmd.args.user_id_status
  local user_code = cmd.args.user_code
  local code_id = cmd.args.user_identifier

  if reported_user_id_status == user_id_status.ENABLED_GRANT_ACCESS or -- OCCUPIED in UserCodeV1
      (reported_user_id_status == user_id_status.STATUS_NOT_AVAILABLE and user_code ~= nil) then
    local code_state = device:get_field(constants.CODE_STATE)
    return user_code == "**********" or user_code == nil or (code_state ~= nil and code_state["setName"..cmd.args.user_identifier] ~= nil)
  else
    return (code_id == 0 and reported_user_id_status == user_id_status.AVAILABLE) or
          reported_user_id_status == user_id_status.STATUS_NOT_AVAILABLE
  end
end

local function user_code_report_handler(self, device, cmd)
  local code_id = cmd.args.user_identifier
  if is_user_code_report_mfr_specific(device, cmd) then
    local reported_user_id_status = cmd.args.user_id_status
    local user_code = cmd.args.user_code
    local event

    if reported_user_id_status == user_id_status.ENABLED_GRANT_ACCESS or -- OCCUPIED in UserCodeV1
        (reported_user_id_status == user_id_status.STATUS_NOT_AVAILABLE and user_code ~= nil) then
      local code_name = LockCodesDefaults.get_code_name(device, code_id)
      local change_type = LockCodesDefaults.get_change_type(device, code_id)
      event = capabilities.lockCodes.codeChanged(code_id..""..change_type, { state_change = true })
      event.data = {codeName = code_name}
      if code_id ~= 0 then -- ~= MASTER_CODE
        LockCodesDefaults.code_set_event(device, code_id, code_name)
      end
    elseif code_id == 0 and reported_user_id_status == user_id_status.AVAILABLE then
      local lock_codes = LockCodesDefaults.get_lock_codes(device)
      for _code_id, _ in pairs(lock_codes) do
        LockCodesDefaults.code_deleted(device, _code_id)
      end
      device:emit_event(capabilities.lockCodes.lockCodes(json.encode(LockCodesDefaults.get_lock_codes(device)), { visibility = { displayed = false } }))
    else -- user_id_status.STATUS_NOT_AVAILABLE
      event = capabilities.lockCodes.codeChanged(code_id.." failed", { state_change = true })
    end

    if event ~= nil then
      device:emit_event(event)
    end
    LockCodesDefaults.clear_code_state(device, code_id)
    LockCodesDefaults.verify_set_code_completion(device, cmd, code_id)
  else
    LockCodesDefaults.zwave_handlers[cc.USER_CODE][UserCode.REPORT](self, device, cmd)
  end
end

local schlage_lock = {
  capability_handlers = {
    [capabilities.lockCodes.ID] = {
      [capabilities.lockCodes.commands.setCodeLength.NAME] = set_code_length,
      [capabilities.lockCodes.commands.reloadAllCodes.NAME] = reload_all_codes,
      [capabilities.lockCodes.commands.setCode.NAME] = set_code
    }
  },
  zwave_handlers = {
    [cc.USER_CODE] = {
      [UserCode.REPORT] = user_code_report_handler
    },
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report
    },
    [cc.BASIC] = {
      [Basic.SET] = basic_set_handler
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
  },
  NAME = "Schlage Lock",
  can_handle = can_handle_schlage_lock,
}

return schlage_lock
