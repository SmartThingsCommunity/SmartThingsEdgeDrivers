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

  -- programming users cannot be created through the capability
  if command.args.userType == consts.PROGRAMMING_USER.USER_TYPE then
    lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.ADD, consts.COMMAND_RESULT.INVALID_COMMAND)
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

  -- a user cannot be made a programming user, and a programming user cannot be changed to another type
  local found_user = tables.find_entry(device, "users", command.args.userIndex)
  local is_programming_user = found_user ~= nil and found_user.userType == consts.PROGRAMMING_USER.USER_TYPE
  if (command.args.userType == consts.PROGRAMMING_USER.USER_TYPE) ~= is_programming_user then
    lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.UPDATE, consts.COMMAND_RESULT.INVALID_COMMAND)
    return
  end

  -- a user that does not exist is not created here, so this fails for it
  local result_status = tables.update_entry(device, "users",
    command.args.userIndex,
    { userName = command.args.userName, userType = command.args.userType }
  )

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

  -- userIndex 0 means "create a new user for this credential" (its index is chosen when the lock confirms the
  -- code). Any other userIndex must name an existing user that does not already have a credential (for now,
  -- each user may have at most one credential).
  -- A programming user cannot be created or given a credential through the capability.
  local user_index = command.args.userIndex
  if command.args.userType == consts.PROGRAMMING_USER.USER_TYPE
      or user_index ~= 0 and (not tables.find_entry(device, "users", user_index)
      or lock_utils.is_programming_user(device, user_index)
      or tables.find_entry_by(device, "credentials", "userIndex", user_index)) then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.ADD, consts.COMMAND_RESULT.INVALID_COMMAND)
    return
  end

  local credentials_full = tables.is_full(device, "credentials")
  -- if we are being asked to create a new user (index 0), this also needs a free user index.
  local users_full = (user_index == 0) and tables.is_full(device, "users")
  if credentials_full or users_full then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.ADD, consts.COMMAND_RESULT.RESOURCE_EXHAUSTED)
    return
  end

  -- the credential always takes the next available slot.
  local cred_index = tables.next_index(device, "credentials")

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
  -- Index 0 is the Z-Wave "all users" wildcard and is never a valid credential to update.
  if command.args.credentialIndex == 0 then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.UPDATE, consts.COMMAND_RESULT.INVALID_COMMAND)
    return
  end

  if lock_utils.is_device_busy(device) then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.UPDATE, consts.COMMAND_RESULT.BUSY)
    return
  end

  local existing = tables.find_entry(device, "credentials", command.args.credentialIndex)
  if not existing then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.UPDATE, consts.COMMAND_RESULT.FAILURE)
    return
  end

  -- a credential cannot be moved to another user: the given userIndex must already own this credential
  if existing.userIndex ~= command.args.userIndex then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.UPDATE, consts.COMMAND_RESULT.INVALID_COMMAND)
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

-- The programming code cannot be deleted. Fail the command without sending anything to the lock.
local function refuse_programming_credential_delete(device, injected_by_delete_user)
  device.log.warn("ignoring deleteCredential for a programming code, it cannot be deleted")
  if injected_by_delete_user then
    lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.DELETE, consts.COMMAND_RESULT.FAILURE)
    lock_utils.clear_busy_state(device)
  end
  lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE, consts.COMMAND_RESULT.FAILURE)
end

function CapabilityHandlers.delete_credential(driver, device, command)
  -- Index 0 is the Z-Wave "all users" wildcard; clearing everything must go through deleteAllCredentials.
  if command.args.credentialIndex == 0 then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE, consts.COMMAND_RESULT.INVALID_COMMAND)
    return
  end

  local credential_index
  if device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS) == consts.LOCK_USERS.DELETE then
    -- Injected by deleteUser; busy state was already set with the full LOCK_USERS.DELETE context.
    local credential_args = device:get_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE) or {}
    if lock_utils.is_programming_user(device, credential_args.userIndex) then
      refuse_programming_credential_delete(device, true)
      return
    end
    credential_index = credential_args.credentialIndex
  elseif lock_utils.is_device_busy(device) then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE, consts.COMMAND_RESULT.BUSY)
    return
  else
    -- Standalone deleteCredential: look up the credential to obtain its associated userIndex.
    local found_cred = tables.find_entry(device, "credentials", command.args.credentialIndex)
    if not found_cred then
      lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE, consts.COMMAND_RESULT.FAILURE)
      return
    end
    if lock_utils.is_programming_user(device, found_cred.userIndex) then
      refuse_programming_credential_delete(device, false)
      return
    end
    lock_utils.set_busy_state(device, consts.LOCK_CREDENTIALS.DELETE, {
      credentialIndex = command.args.credentialIndex,
      credentialType  = command.args.credentialType,
      userIndex       = found_cred.userIndex,
    })
    credential_index = command.args.credentialIndex
  end

  device:send(UserCode:Set({
    user_identifier = credential_index,
    user_id_status = UserCode.user_id_status.AVAILABLE
  }))
end

function CapabilityHandlers.delete_all_credentials(driver, device, command)
  local cmd_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)

  local send_clear_commands = function()
    -- User Identifier 0 with status AVAILABLE tells the lock to clear every user code slot. A lock with a
    -- programming code (Yale) keeps it, so the programming entries are kept in state below.
    device:send(UserCode:Set({
      user_identifier = 0,
      user_id_status = UserCode.user_id_status.AVAILABLE
    }))
    -- Delayed cleanup: ensure all tables are cleared after the lock has processed the command
    device.thread:call_with_delay(4, function()
      if cmd_in_progress == consts.LOCK_USERS.DELETE_ALL then
        lock_utils.delete_all_non_programming_entries(device, "users")
        lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.DELETE_ALL, consts.COMMAND_RESULT.SUCCESS)
      end
      lock_utils.delete_all_non_programming_entries(device, "credentials")
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

  if device:supports_capability(capabilities.battery) then
    device:send(Battery:Get({}))
  end

  if device:supports_capability(capabilities.lockCredentials) then
    -- If we are missing the cached values for these attributes, read them so we can properly manage them locally
    if (device:get_latest_state("main", capabilities.lockCredentials.ID, capabilities.lockCredentials.pinUsersSupported.NAME) == nil) or
       (device:get_latest_state("main", capabilities.lockUsers.ID, capabilities.lockUsers.totalUsersSupported.NAME) == nil) then
      device:send(UserCode:UsersNumberGet({}))
    end

    -- Allow callers to try to sync device state- fails silently if the device is busy or already synced.
    device.thread:call_with_delay(15, function() lock_utils.sync_device_state(device) end)
  end
end

return CapabilityHandlers
