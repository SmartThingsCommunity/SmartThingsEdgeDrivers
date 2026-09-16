-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local consts = require "lock_utils.constants"
local tables = require "lock_utils.tables"

local lock_utils = {}

-- [[ BUSY STATE MANAGEMENT ]] --

-- Check if we are currently busy performing a task, or at least 10 seconds have passed since the busy state was last set.
-- If busy, return true. If not busy, clear any stale state and return false.
function lock_utils.is_device_busy(device)
  local c_time = os.time()
  local busy_since = device:get_field(consts.DRIVER_STATE.BUSY) or false

  if (busy_since == false) or (c_time - busy_since > 10) then
    lock_utils.clear_busy_state(device)
    return false
  end
  return true
end

-- Set states that may be required when in busy state
function lock_utils.set_busy_state(device, command_name, command_args)
  device:set_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS, command_name)
  device:set_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE, command_args or {})
  device:set_field(consts.DRIVER_STATE.BUSY, os.time())
end

-- Clear states that were set when in busy state
function lock_utils.clear_busy_state(device)
  device:set_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS, nil)
  device:set_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE, nil)
  device:set_field(consts.DRIVER_STATE.BUSY, false)
end


-- [[ SYNC STATE MANAGEMENT ]] --

function lock_utils.sync_device_state(device)
  local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })

  if (device:get_field(consts.SYNC.CODE_INDEX) == nil) then
    device:set_field(consts.SYNC.CODE_INDEX, 1)
  end
  lock_utils.set_busy_state(device, consts.SYNC.CODES_FROM_LOCK)
  device:send(UserCode:Get({user_identifier = device:get_field(consts.SYNC.CODE_INDEX)}))
end


-- [[ COMMAND RESULT STATE MANAGEMENT ]] --

function lock_utils.emit_command_result(device, capability, command_name, status_code, additional_info)
  local info = additional_info or {}
  info.commandName = command_name
  info.statusCode = status_code
  if capability then
    device:emit_event(capability.commandResult(info, {state_change = true, visibility = {displayed = false}}))
  end
end


-- [[ HELPERS ]] --

function lock_utils.get_code_id_from_notification_event(event_params, v1_alarm_level)
  local code_id = v1_alarm_level
  if event_params ~= nil and event_params ~= "" then
    event_params = {event_params:byte(1,-1)}
    code_id = (#event_params == 1) and event_params[1] or event_params[3]
  end
  return tostring(code_id)
end

function lock_utils.set_credential_report_helper(device, credential_index)
  -- cached values from capability command
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  local credential_args = device:get_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE) or {}

  local result_status
  if command_in_progress == consts.LOCK_CREDENTIALS.ADD then
    result_status = tables.add_entry(device, "credentials", {
      userIndex       = credential_args.userIndex,
      credentialIndex = credential_args.credentialIndex,
      credentialType  = consts.CRED_TYPE_PIN,
      credentialName  = credential_args.credentialName,
    })
  elseif command_in_progress == consts.LOCK_CREDENTIALS.UPDATE then
    result_status = consts.COMMAND_RESULT.SUCCESS
  elseif not tables.find_entry(device, "credentials", credential_index) then
    -- credential does not exist and no add/update command in progress, therefore it was added out-of-band
    -- check what user slot we have to associate this with, and add a default user
    local next_available_index = tables.next_index(device, "users")
    if next_available_index <= tables.get_max_entries(device, "users") then
      tables.add_entry(device, "users", {
        userIndex = next_available_index,
        userName  = "Guest " .. next_available_index,
        userType  = "guest",
      })
      tables.add_entry(device, "credentials", {
        userIndex       = next_available_index,
        credentialIndex = credential_index,
        credentialType  = consts.CRED_TYPE_PIN,
        credentialName  = "Guest " .. next_available_index,
      })
    end
  end

  -- emit command result
  if command_in_progress and result_status then
    local additional_info = result_status == consts.COMMAND_RESULT.SUCCESS and {
      userIndex       = credential_args.userIndex,
      credentialIndex = credential_args.credentialIndex,
    } or nil
    lock_utils.emit_command_result(device, capabilities.lockCredentials, command_in_progress, result_status, additional_info)
    lock_utils.clear_busy_state(device)
  end
end

function lock_utils.delete_credential_report_helper(device, credential_index)
  -- cached values from capability command
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  local credential_args_in_use = device:get_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE)

  local user_status, credential_status
  if command_in_progress == consts.LOCK_USERS.DELETE then
    user_status = tables.delete_entry(device, "users", credential_args_in_use.userIndex)
    credential_status = tables.delete_entry(device, "credentials", credential_args_in_use.credentialIndex)
  elseif command_in_progress == consts.LOCK_CREDENTIALS.DELETE then
    credential_status = tables.delete_entry(device, "credentials", credential_args_in_use.credentialIndex)
  else
    -- out-of-band deletion, find the credential index and associated user to delete
    local credential = tables.find_entry(device, "credentials", credential_index)
    if credential then
      credential_status = tables.delete_entry(device, "credentials", credential_index)
      local associated_user = tables.find_entry_by(device, "users", "userIndex", credential.userIndex)
      if associated_user then
        tables.delete_entry(device, "users", credential.userIndex)
      end
    end
  end

  -- emit command results
  if command_in_progress == consts.LOCK_USERS.DELETE and user_status and credential_status then
    -- the deleteUser command injects a deleteCredential command, so both command results should be emitted in this case.
    local user_info = user_status == consts.COMMAND_RESULT.SUCCESS and { userIndex = credential_args_in_use.userIndex } or nil
    local cred_info = credential_status == consts.COMMAND_RESULT.SUCCESS and { credentialIndex = credential_args_in_use.credentialIndex, userIndex = credential_args_in_use.userIndex } or nil
    lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.DELETE, user_status, user_info)
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE, credential_status, cred_info)
    lock_utils.clear_busy_state(device)
  elseif command_in_progress == consts.LOCK_CREDENTIALS.DELETE and credential_status then
    local cred_info = credential_status == consts.COMMAND_RESULT.SUCCESS and { credentialIndex = credential_args_in_use.credentialIndex, userIndex = credential_args_in_use.userIndex } or nil
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE, credential_status, cred_info)
    lock_utils.clear_busy_state(device)
  end
end


return lock_utils
