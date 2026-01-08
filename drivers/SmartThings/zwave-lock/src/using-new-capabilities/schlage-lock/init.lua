-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local cc = require "st.zwave.CommandClass"
local constants = require "st.zwave.constants"

local UserCode = (require "st.zwave.CommandClass.UserCode")({version=1})
local user_id_status = UserCode.user_id_status
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=2})
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local Association = (require "st.zwave.CommandClass.Association")({version=1})

local lock_utils = require "new_lock_utils"

local SCHLAGE_LOCK_CODE_LENGTH_PARAM = {number = 16, size = 1}

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
    local current_code_length = device:get_latest_state("main", capabilities.lockCredentials.ID, capabilities.lockCredentials.minPinCodeLen.NAME)
    if current_code_length ~= nil and current_code_length ~= reported_code_length then
      -- when the code length is changed, all the codes have been wiped
      for _, credential in pairs(lock_utils.get_credentials(device)) do
        lock_utils.delete_credential(device, credential.credentialIndex)
      end
      lock_utils.send_events(device)
    end
    device:emit_event(capabilities.lockCredentials.minPinCodeLen(reported_code_length))
    device:emit_event(capabilities.lockCredentials.maxPinCodeLen(reported_code_length))
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
  local credential_index = cmd.args.user_identifier
  if is_user_code_report_mfr_specific(device, cmd) then
    local reported_user_id_status = cmd.args.user_id_status

    if credential_index == 0 and reported_user_id_status == user_id_status.AVAILABLE then
      -- master code changed, clear all credentials
      for _, credential in pairs(lock_utils.get_credentials(device)) do
        lock_utils.delete_credential(device, credential.credentialIndex)
      end
      lock_utils.send_events(device)
    end
  else
    local new_capabilities = require "using-new-capabilities"
    new_capabilities.zwave_handlers[cc.USER_CODE][UserCode.REPORT](self, device, cmd)
  end
end

local function add_credential_handler(self, device, cmd)
  local DEFAULT_COMMANDS_DELAY = 4.2
  local current_code_length = device:get_latest_state("main", capabilities.lockCredentials.ID, capabilities.lockCredentials.minPinCodeLen.NAME)
  local base_handler = function()
    local new_capabilities = require "using-new-capabilities"
    new_capabilities.capability_handlers[capabilities.lockCredentials.ID][capabilities.lockCredentials.commands.addCredential.NAME](self, device, cmd)
  end
  if current_code_length == nil then
    device:send(Configuration:Get({parameter_number = SCHLAGE_LOCK_CODE_LENGTH_PARAM.number}))
    device.thread:call_with_delay(DEFAULT_COMMANDS_DELAY, base_handler)
  else
    base_handler()
  end
end

local schlage_lock = {
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
  capability_handlers = {
    [capabilities.lockCredentials.ID] = {
      [capabilities.lockCredentials.commands.addCredential.NAME] = add_credential_handler
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
  },
  NAME = "Schlage Lock",
  can_handle = require("using-new-capabilities.schlage-lock.can_handle"),
}

return schlage_lock
