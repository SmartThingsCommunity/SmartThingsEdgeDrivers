-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities   = require "st.capabilities"
local cc             = require "st.zwave.CommandClass"
local Notification   = (require "st.zwave.CommandClass.Notification")({version=3})
local UserCode       = (require "st.zwave.CommandClass.UserCode")({version=1})

local consts         = require "lock_utils.constants"
local lock_utils     = require "lock_utils.utils"
local tables         = require "lock_utils.tables"
local yale_admin     = require "yale-lock.admin"
local zwave_handlers = require "lock_handlers.zwave_responses"
local cap_handlers   = require "lock_handlers.capabilities"

-- Yale locks keep their admin code in a user code slot that is not one of the lock's user slots. It is exposed
-- like any other credential, owned by a user that has the same index and the admin code userType.
local function is_admin_credential(device, credential_index)
  return credential_index ~= nil and credential_index == yale_admin.credential_index(device)
end

-- Add the admin code credential and the user that owns it. Both use the admin code slot as their index,
-- since the user index only has meaning inside the capability state.
local function add_admin_entries(device, credential_index, name)
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

-- Record the admin code and, if an addCredential for the admin code is in progress, report the result. A
-- command in progress for any other credential is left alone.
local function admin_code_reported(device)
  local admin_index = yale_admin.credential_index(device)
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  local credential_args = device:get_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE) or {}
  local adding_admin = command_in_progress == consts.LOCK_CREDENTIALS.ADD and
  credential_args.credentialIndex == admin_index
  local status = add_admin_entries(device, admin_index, adding_admin and credential_args.credentialName or nil)
  if adding_admin then
    local additional_info = status == consts.COMMAND_RESULT.SUCCESS and {
      userIndex       = credential_args.userIndex,
      credentialIndex = credential_args.credentialIndex,
    } or nil
    lock_utils.emit_command_result(device, capabilities.lockCredentials, command_in_progress, status, additional_info)
    lock_utils.clear_busy_state(device)
  end
end

-- True if an update or delete of the admin code is waiting on the lock. The lock confirms or refuses it like
-- any other credential, so its reports go to the generic handlers.
local function is_admin_change_in_progress(device)
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  local credential_args = device:get_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE) or {}
  return command_in_progress ~= consts.LOCK_CREDENTIALS.ADD and
    is_admin_credential(device, credential_args.credentialIndex)
end

local function user_code_report(driver, device, cmd)
  local credential_index = cmd.args.user_identifier
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  local occupied = lock_utils.is_code_occupied(cmd)

  -- a report of the admin code slot records the admin code, unless it answers an update or delete of the
  -- admin code (handled like any other credential).
  if is_admin_credential(device, credential_index) and occupied and not is_admin_change_in_progress(device) then
    admin_code_reported(device)
    -- a sync only moves on when the slot it asked for is reported. The admin code is already recorded, so
    -- the sync does not add it again.
    if command_in_progress ~= consts.SYNC.CODES_FROM_LOCK or
       credential_index ~= device:get_field(consts.SYNC.CODE_INDEX) then
      return
    end
  end

  local was_syncing = command_in_progress == consts.SYNC.CODES_FROM_LOCK
  zwave_handlers.user_code_report(driver, device, cmd)
  if was_syncing and device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS) ~= consts.SYNC.CODES_FROM_LOCK then
    -- the sync is finished. The admin code slot is outside the lock's user code slots, so it is read separately.
    yale_admin.read_admin_code(device)
  end
end

local function notification_report(driver, device, cmd)
  if cmd.args.notification_type == Notification.notification_type.ACCESS_CONTROL then
    local access_control_event = Notification.event.access_control
    local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
    local credential_args = device:get_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE) or {}
    if cmd.args.event == access_control_event.NEW_USER_CODE_ADDED and
       is_admin_credential(device, tonumber(lock_utils.get_code_id_from_notification_event(
         cmd.args.event_parameter, cmd.args.v1_alarm_level))) and not is_admin_change_in_progress(device) then
      -- the lock confirms a write to the admin code slot like any other user code (ZW2). An update of the
      -- admin code is completed by the generic handler.
      admin_code_reported(device)
      return
    elseif cmd.args.event == access_control_event.NEW_PROGRAM_CODE_ENTERED_UNIQUE_CODE_FOR_LOCK_CONFIGURATION and
       command_in_progress == consts.LOCK_CREDENTIALS.ADD and
       is_admin_credential(device, credential_args.credentialIndex) then
      -- the "master code changed" event is sent instead of NEW_USER_CODE_ADDED by other modules (ZW3), so it
      -- completes an addCredential in progress.
      admin_code_reported(device)
      return
    end
  end
  zwave_handlers.notification_report(driver, device, cmd)
end

local function add_credential(driver, device, command)
  local cred_index = command.args.userIndex
  if not is_admin_credential(device, cred_index) then
    cap_handlers.add_credential(driver, device, command)
    return
  end

  -- only an admin code credential may be written to the admin code slot, and it is not limited by the lock's
  -- user slots
  if command.args.userType ~= consts.ADMIN.USER_TYPE then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.ADD, consts.COMMAND_RESULT.INVALID_COMMAND)
    return
  end
  if lock_utils.is_device_busy(device) then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.ADD, consts.COMMAND_RESULT.BUSY)
    return
  end
  -- writing the slot would replace the admin code on the lock, which is what updateCredential is for
  if tables.find_entry(device, "credentials", cred_index) then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.ADD, consts.COMMAND_RESULT.OCCUPIED)
    return
  end

  cap_handlers.send_add_credential(device, cred_index, cred_index, command)
end

local function add_user(driver, device, command)
  -- the admin code user is added with the admin code credential, never on its own in a user slot
  if command.args.userType == consts.ADMIN.USER_TYPE then
    lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.ADD, consts.COMMAND_RESULT.INVALID_COMMAND)
    return
  end
  cap_handlers.add_user(driver, device, command)
end

local function update_user(driver, device, command)
  -- the admin code user cannot be changed to another type, and no other user can be made an admin code user
  if (command.args.userType == consts.ADMIN.USER_TYPE) ~= is_admin_credential(device, command.args.userIndex) then
    lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.UPDATE, consts.COMMAND_RESULT.INVALID_COMMAND)
    return
  end
  cap_handlers.update_user(driver, device, command)
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
    [capabilities.lockUsers.ID] = {
      [capabilities.lockUsers.commands.addUser.NAME] = add_user,
      [capabilities.lockUsers.commands.updateUser.NAME] = update_user
    },
    [capabilities.lockCredentials.ID] = {
      [capabilities.lockCredentials.commands.addCredential.NAME] = add_credential
    }
  },
  NAME = "Yale Lock",
  can_handle = require("yale-lock.can_handle"),
}

return yale_lock
