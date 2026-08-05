-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local lock_utils   = require "lock_utils.utils"
local tables       = require "lock_utils.tables"
local consts       = require "lock_utils.constants"

--- @type st.zwave.CommandClass.DoorLock
local DoorLock     = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
--- @type st.zwave.CommandClass.Battery
local Battery      = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.UserCode
local UserCode     = (require "st.zwave.CommandClass.UserCode")({ version = 1 })


local CapabilityHandlers = {}


-- [[ LOCK USERS CAPABILITY COMMANDS ]] --

function CapabilityHandlers.add_user(driver, device, command)
  if lock_utils.is_device_busy(device) then
    lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.ADD, consts.COMMAND_RESULT.BUSY)
    return
  end

  -- Find the smallest positive userIndex not already in the table
  local next_available_index = tables.next_index(device, "users")
  local status = tables.add_entry(device, "users", {
    userIndex = next_available_index,
    userName  = command.args.userName,
    userType  = command.args.userType,
  })
  local additional_info = status == consts.COMMAND_RESULT.SUCCESS and { userIndex = next_available_index }
  lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.ADD, status, additional_info)
end

function CapabilityHandlers.update_user(driver, device, command)
  if lock_utils.is_device_busy(device) then
    lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.UPDATE, consts.COMMAND_RESULT.BUSY)
    return
  end

  local result_status
  if not tables.find_entry(device, "users", command.args.userIndex) then
    result_status = tables.add_entry(device, "users", {
      userIndex = command.args.userIndex,
      userName  = command.args.userName,
      userType  = command.args.userType,
    })
  else
    result_status = tables.update_entry(device, "users",
      command.args.userIndex,
      { userName = command.args.userName, userType = command.args.userType }
    )
  end

  local additional_info = result_status == consts.COMMAND_RESULT.SUCCESS and { userIndex = command.args.userIndex }
  lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.UPDATE, result_status, additional_info)
end

function CapabilityHandlers.delete_user(driver, device, command)
  if lock_utils.is_device_busy(device) then
    lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.DELETE, consts.COMMAND_RESULT.BUSY)
    return
  end

  local associated_credentials = tables.find_all_entries_by(device, "credentials", "userIndex", command.args.userIndex)
  for _, associated_credential in ipairs(associated_credentials) do
    -- Set busy state with the full user+credential context BEFORE injecting.
    -- Injected capability commands are schema-validated, so extra args like userIndex
    -- would be stripped. By setting device fields here we preserve the full context.
    lock_utils.set_busy_state(device, consts.LOCK_USERS.DELETE, {
      userIndex       = command.args.userIndex,
      credentialIndex = associated_credential.credentialIndex,
      credentialType  = consts.CRED_TYPE_PIN,
    })
    driver:inject_capability_command(device, {
      capability = capabilities.lockCredentials.ID,
      command    = capabilities.lockCredentials.commands.deleteCredential.NAME,
      args = {
        credentialIndex = associated_credential.credentialIndex,
        credentialType  = consts.CRED_TYPE_PIN,
      }
    })
  end
  if #associated_credentials == 0 then
    -- No associated credentials: delete the user entry directly and report the result
    local status = tables.delete_entry(device, "users", command.args.userIndex)
    local additional_info = status == consts.COMMAND_RESULT.SUCCESS and { userIndex = command.args.userIndex }
    lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.DELETE, status, additional_info)
  end
end

function CapabilityHandlers.delete_all_users(driver, device, command)
  if lock_utils.is_device_busy(device) then
    lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.DELETE_ALL, consts.COMMAND_RESULT.BUSY)
    return
  end
  -- Set busy state with DELETE_ALL context BEFORE injecting so the response handler
  -- knows to clear both tables and emit results for both capabilities.
  lock_utils.set_busy_state(device, consts.LOCK_USERS.DELETE_ALL, {})
  driver:inject_capability_command(device, {
    capability = capabilities.lockCredentials.ID,
    command    = capabilities.lockCredentials.commands.deleteAllCredentials.NAME,
    args       = { credentialType = consts.CRED_TYPE_PIN }
  })
end


-- [[ LOCK CREDENTIALS CAPABILITY COMMANDS ]] --

function CapabilityHandlers.add_credential(driver, device, command)
  if lock_utils.is_device_busy(device) then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.ADD, consts.COMMAND_RESULT.BUSY)
    return
  end

  -- A userIndex of 0 means "auto-assign the next available slot"
  local user_index = command.args.userIndex == 0 and tables.next_index(device, "users") or command.args.userIndex
  local cred_index = command.args.userIndex == 0 and tables.next_index(device, "credentials") or command.args.userIndex

  if #(tables.get_state(device, "credentials") or {}) >= tables.get_max_entries(device, "credentials") then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.ADD, consts.COMMAND_RESULT.RESOURCE_EXHAUSTED)
    return
  end

  -- Set busy state and attempt to set the PIN on-device.
  lock_utils.set_busy_state(device, consts.LOCK_CREDENTIALS.ADD, {
    userIndex       = user_index,
    credentialIndex = cred_index,
    credentialType  = command.args.credentialType,
    credentialName  = command.args.credentialName,
  })
  device:send(UserCode:Set({
    user_identifier = cred_index,
    user_code = command.args.credentialData,
    user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
  }))
end

function CapabilityHandlers.update_credential(driver, device, command)
  if lock_utils.is_device_busy(device) then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.UPDATE, consts.COMMAND_RESULT.BUSY)
    return
  end

  if not tables.find_entry(device, "credentials", command.args.credentialIndex) then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.UPDATE, consts.COMMAND_RESULT.FAILURE)
    return
  end

  lock_utils.set_busy_state(device, consts.LOCK_CREDENTIALS.UPDATE, {
    userIndex       = command.args.userIndex,
    credentialIndex = command.args.credentialIndex,
    credentialType  = command.args.credentialType,
    credentialName  = command.args.credentialName,
  })
  device:send(UserCode:Set({
    user_identifier = command.args.credentialIndex,
    user_code = command.args.credentialData,
    user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
  }))
end

function CapabilityHandlers.delete_credential(driver, device, command)
  local cmd_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)

  if cmd_in_progress == consts.LOCK_USERS.DELETE then
    -- Injected by deleteUser; busy state was already set with the full LOCK_USERS.DELETE context.
    local credential_args = device:get_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE) or {}
    device:send(UserCode:Set({
      user_identifier = credential_args.credentialIndex,
      user_id_status = UserCode.user_id_status.AVAILABLE
    }))
  elseif lock_utils.is_device_busy(device) then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE, consts.COMMAND_RESULT.BUSY)
  else
    -- Standalone deleteCredential: look up the credential to obtain its associated userIndex.
    local found_cred = tables.find_entry(device, "credentials", command.args.credentialIndex)
    if not found_cred then
      lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE, consts.COMMAND_RESULT.FAILURE)
      return
    end
    lock_utils.set_busy_state(device, consts.LOCK_CREDENTIALS.DELETE, {
      credentialIndex = command.args.credentialIndex,
      credentialType  = command.args.credentialType,
      userIndex       = found_cred.userIndex,
    })
    device:send(UserCode:Set({
      user_identifier = command.args.credentialIndex,
      user_id_status = UserCode.user_id_status.AVAILABLE
    }))
  end
end

function CapabilityHandlers.delete_all_credentials(driver, device, command)
  local cmd_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)

  local send_clear_commands = function()
    local credentials = tables.get_state(device, "credentials") or {}
    local delay = 0
    for _, credential in ipairs(credentials) do
      device.thread:call_with_delay(delay, function()
        device:send(UserCode:Set({
          user_identifier = credential.credentialIndex,
          user_id_status = UserCode.user_id_status.AVAILABLE
        }))
      end)
      delay = delay + 2
    end
    -- Delayed cleanup: ensure all tables are cleared after individual responses complete
    device.thread:call_with_delay(delay + 4, function()
      if cmd_in_progress == consts.LOCK_USERS.DELETE_ALL then
        tables.delete_all_entries(device, "users")
        lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.DELETE_ALL, consts.COMMAND_RESULT.SUCCESS)
      end
      tables.delete_all_entries(device, "credentials")
      lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE_ALL, consts.COMMAND_RESULT.SUCCESS)
      lock_utils.clear_busy_state(device)
    end)
  end

  if cmd_in_progress == consts.LOCK_USERS.DELETE_ALL then
    -- Injected by deleteAllUsers; busy state was already set with LOCK_USERS.DELETE_ALL context.
    send_clear_commands()
  elseif lock_utils.is_device_busy(device) then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE_ALL, consts.COMMAND_RESULT.BUSY)
  else
    lock_utils.set_busy_state(device, consts.LOCK_CREDENTIALS.DELETE_ALL, command.args)
    send_clear_commands()
  end
end


-- [[ REFRESH CAPABILITY COMMANDS ]] --

function CapabilityHandlers.refresh(driver, device, cmd)
  device:send(DoorLock:OperationGet({}))
  device:send(Battery:Get({}))

  if device:supports_capability(capabilities.lockCredentials) then
    -- If we are missing the cached values for these attributes, read them so we can properly manage them locally
    if (device:get_latest_state("main", capabilities.lockCredentials.ID, capabilities.lockCredentials.pinUsersSupported.NAME) == nil) or
       (device:get_latest_state("main", capabilities.lockUsers.ID, capabilities.lockUsers.totalUsersSupported.NAME) == nil) then
      device:send(UserCode:UsersNumberGet({}))
    end
  end
end

return CapabilityHandlers
