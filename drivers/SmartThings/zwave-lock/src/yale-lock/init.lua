-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local cc = require "st.zwave.CommandClass"
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local UserCode = (require "st.zwave.CommandClass.UserCode")({version=1})
local user_id_status = UserCode.user_id_status

local consts         = require "lock_utils.constants"
local lock_utils     = require "lock_utils.utils"
local tables         = require "lock_utils.tables"
local zwave_handlers = require "lock_handlers.zwave_responses"
local cap_handlers   = require "lock_handlers.capabilities"

-- Yale locks keep their master code in a user code slot that is not one of the lock's user slots. It is exposed
-- like any other credential, owned by a user that has the same index and the master code userType.

local function is_master_credential(device, credential_index)
  return credential_index ~= nil and credential_index == tables.master_credential_index(device)
end

-- Add the master code credential and the user that owns it. Both use the master code slot as their index,
-- since the user index only has meaning inside the capability state.
local function add_master_entries(device, credential_index, name)
  name = name or consts.ADMIN.NAME
  local status = tables.add_entry(device, "users", {
    userIndex = credential_index,
    userName  = name,
    userType  = consts.ADMIN.USER_TYPE,
  }, true)
  if status ~= consts.COMMAND_RESULT.SUCCESS and status ~= consts.COMMAND_RESULT.OCCUPIED then return status end
  return tables.add_entry(device, "credentials", {
    userIndex       = credential_index,
    credentialIndex = credential_index,
    credentialType  = consts.CRED_TYPE_PIN,
    credentialName  = name,
  }, true)
end

-- Record the master code and, if an addCredential for the master code is in progress, report the result. A
-- command in progress for any other credential is left alone.
local function master_code_reported(device)
  local master_index = tables.master_credential_index(device)
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  local credential_args = device:get_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE) or {}
  if command_in_progress == consts.LOCK_CREDENTIALS.ADD and credential_args.credentialIndex == master_index then
    local status = add_master_entries(device, master_index, credential_args.credentialName)
    local additional_info = status == consts.COMMAND_RESULT.SUCCESS and {
      userIndex       = credential_args.userIndex,
      credentialIndex = credential_args.credentialIndex,
    } or nil
    lock_utils.emit_command_result(device, capabilities.lockCredentials, command_in_progress, status, additional_info)
    lock_utils.clear_busy_state(device)
  else
    add_master_entries(device, master_index)
  end
end

local function user_code_report(driver, device, cmd)
  local credential_index = cmd.args.user_identifier
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  local occupied = cmd.args.user_id_status == user_id_status.ENABLED_GRANT_ACCESS or
    (cmd.args.user_id_status == user_id_status.STATUS_NOT_AVAILABLE and cmd.args.user_code)

  -- a report of the master code slot while it is added, or with no command in progress, records the master code.
  -- Anything else (a delete the lock refused, an update) is handled like any other credential.
  if is_master_credential(device, credential_index) and occupied and
     (command_in_progress == nil or command_in_progress == consts.LOCK_CREDENTIALS.ADD) then
    master_code_reported(device)
    return
  end

  local was_syncing = command_in_progress == consts.SYNC.CODES_FROM_LOCK
  zwave_handlers.user_code_report(driver, device, cmd)
  if was_syncing and device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS) ~= consts.SYNC.CODES_FROM_LOCK then
    -- the sync is finished. The master code slot is outside the lock's user code slots, so it is read separately.
    lock_utils.read_master_code(device)
  end
end

local function notification_report(driver, device, cmd)
  if cmd.args.notification_type == Notification.notification_type.ACCESS_CONTROL then
    local access_control_event = Notification.event.access_control
    local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
    local credential_args = device:get_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE) or {}
    if cmd.args.event == access_control_event.NEW_USER_CODE_ADDED and
       is_master_credential(device, tonumber(lock_utils.get_code_id_from_notification_event(
         cmd.args.event_parameter, cmd.args.v1_alarm_level))) then
      -- the lock confirms a write to the master code slot like any other user code (ZW2)
      master_code_reported(device)
      return
    elseif cmd.args.event == access_control_event.NEW_PROGRAM_CODE_ENTERED_UNIQUE_CODE_FOR_LOCK_CONFIGURATION and
       command_in_progress == consts.LOCK_CREDENTIALS.ADD and
       is_master_credential(device, credential_args.credentialIndex) then
      -- the "master code changed" event is sent instead of NEW_USER_CODE_ADDED by other modules (ZW3), so it
      -- completes an addCredential in progress.
      master_code_reported(device)
      return
    end
  end
  zwave_handlers.notification_report(driver, device, cmd)
end

local function add_credential(driver, device, command)
  local cred_index = command.args.userIndex
  if not is_master_credential(device, cred_index) then
    cap_handlers.add_credential(driver, device, command)
    return
  end

  -- only a master code credential may be written to the master code slot, and it is not limited by the lock's
  -- user slots
  if command.args.userType ~= consts.ADMIN.USER_TYPE then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.ADD, consts.COMMAND_RESULT.INVALID_COMMAND)
    return
  end
  if lock_utils.is_device_busy(device) then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.ADD, consts.COMMAND_RESULT.BUSY)
    return
  end

  lock_utils.set_busy_state(device, consts.LOCK_CREDENTIALS.ADD, {
    userIndex       = cred_index,
    credentialIndex = cred_index,
    credentialType  = command.args.credentialType,
    credentialName  = command.args.credentialName,
  })
  device:send(UserCode:Set({
    user_identifier = cred_index,
    user_code = command.args.credentialData,
    user_id_status = user_id_status.ENABLED_GRANT_ACCESS
  }))
end

local yale_lock = {
  zwave_handlers = {
    [cc.USER_CODE] = {
      [UserCode.REPORT] = user_code_report
    },
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report
    },
  },
  capability_handlers = {
    [capabilities.lockCredentials.ID] = {
      [capabilities.lockCredentials.commands.addCredential.NAME] = add_credential
    }
  },
  NAME = "Yale Lock",
  can_handle = require("yale-lock.can_handle"),
}

return yale_lock
