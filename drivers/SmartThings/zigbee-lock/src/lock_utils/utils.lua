-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local tables = require "lock_utils.tables"
local consts = require "lock_utils.constants"

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
  local capabilities = require "st.capabilities"
  local clusters = require "st.zigbee.zcl.clusters"

  -- skip if unsupported, already synced, or busy (including a sync already in progress). is_device_busy
  -- expires stale busy state, so a sync that stalled on a lost response can be retried.
  if not (device:supports_capability(capabilities.lockCredentials) and
    device:get_field(consts.SYNC.CODES_SYNCED) ~= consts.SYNC.CODES_SYNC_VERSION and
    not lock_utils.is_device_busy(device)) then
      return
  end

  -- a persisted index from a sync begun under a different sync version is stale; start over.
  if device:get_field(consts.SYNC.CODE_INDEX_VERSION) ~= consts.SYNC.CODES_SYNC_VERSION then
    device:set_field(consts.SYNC.CODE_INDEX, nil, { persist = true })
  end

  -- Per spec, this attribute should be a boolean set to True if it is ok for the door lock server to send PINs over the air.
  device:send(clusters.DoorLock.attributes.SendPINOverTheAir:write(device, true))

  -- if consts.SYNC.CODE_INDEX is nil, we haven't started syncing codes from the lock yet,
  -- so start the process from 0. Persist the index so we can resume if the driver is restarted mid-sync.
  if (device:get_field(consts.SYNC.CODE_INDEX) == nil) then
    device:set_field(consts.SYNC.CODE_INDEX, 0, { persist = true })
    device:set_field(consts.SYNC.CODE_INDEX_VERSION, consts.SYNC.CODES_SYNC_VERSION, { persist = true })
  end
  lock_utils.set_busy_state(device, consts.SYNC.CODES_FROM_LOCK)
  device:send(clusters.DoorLock.server.commands.GetPINCode(device, device:get_field(consts.SYNC.CODE_INDEX)))
end

-- Advance the sync-codes-from-lock flow after a response for the current code index (consts.SYNC.CODE_INDEX).
-- `occupied` is true only when the lock reported an occupied slot at that index.
-- `default_response` is true when the step was resolved by a Default Response: that is not treated as a
-- failure, but it is not an occupied slot either, so it does not count toward the consecutive unoccupied codes.
function lock_utils.continue_code_sync(device, occupied, default_response, is_master)
  local clusters = require "st.zigbee.zcl.clusters"
  local code_index = device:get_field(consts.SYNC.CODE_INDEX)
  if code_index == nil then return end

  if occupied then
    lock_utils.add_reported_credential(device, code_index, is_master)
    -- reset the consecutive unoccupied codes counter since we found an occupied code
    device:set_field(consts.SYNC.CONSECUTIVE_UNOCCUPIED_CODES, 0)
  elseif not default_response then
    device:set_field(consts.SYNC.CONSECUTIVE_UNOCCUPIED_CODES, (device:get_field(consts.SYNC.CONSECUTIVE_UNOCCUPIED_CODES) or 0) + 1)
  end

  if code_index >= tables.get_max_entries(device, "credentials") or
   (device:get_field(consts.SYNC.CONSECUTIVE_UNOCCUPIED_CODES) or 0) > 5 then
    -- stop if we hit the max number of codes supported by the lock, or if we have received 5 consecutive unoccupied codes.
    device:set_field(consts.SYNC.CODE_INDEX, nil, { persist = true })
    device:set_field(consts.SYNC.CONSECUTIVE_UNOCCUPIED_CODES, nil)
    device:set_field(consts.SYNC.RETRIED_CODE_INDEX, nil)
    device:set_field(consts.SYNC.CODES_SYNCED, consts.SYNC.CODES_SYNC_VERSION, { persist = true })
    lock_utils.clear_busy_state(device)
  else
    local next_index = code_index + 1
    device:set_field(consts.SYNC.CODE_INDEX, next_index, { persist = true })
    lock_utils.set_busy_state(device, consts.SYNC.CODES_FROM_LOCK)
    device:send(clusters.DoorLock.server.commands.GetPINCode(device, next_index))
  end
end


-- [[ CREDENTIAL TABLE MANAGEMENT ]] --

-- Add a credential and, optionally, a new user for it. `args.userIndex` is the credential's user.
-- When `add_user` is true the user is created too, so a user never exists without a credential; when false
-- the credential is attached to the already-existing user `args.userIndex`.
-- The credential is added first; the user is only added if that succeeded, so a failed or
-- colliding credential add leaves no user behind. Returns the result status of the credential add.
function lock_utils.add_credential_and_user(device, args, add_user)
  local default_name = "Guest " .. args.userIndex
  if args.userType == consts.MASTER.USER_TYPE then
    default_name = consts.MASTER.DEFAULT_NAME
  elseif args.userType == "admin" then
    default_name = "Admin " .. args.userIndex
  end

  local credential_status = tables.add_entry(device, "credentials", {
    userIndex       = args.userIndex,
    credentialIndex = args.credentialIndex,
    credentialType  = args.credentialType or consts.CRED_TYPE_PIN,
    credentialName  = args.credentialName or default_name,
  })
  if add_user and credential_status == consts.COMMAND_RESULT.SUCCESS then
    tables.add_entry(device, "users", {
      userIndex = args.userIndex,
      userName  = args.userName or args.credentialName or default_name,
      userType  = args.userType or "guest",
    })
  end
  return credential_status
end

-- Apply the arguments of an updateCredential command to the credentials table.
-- Returns the command result status and the credential's userIndex.
function lock_utils.update_commanded_credential(device, credential_args)
  local existing = tables.find_entry(device, "credentials", credential_args.credentialIndex)
  if not existing then return consts.COMMAND_RESULT.FAILURE end
  local name = credential_args.credentialName
  if name ~= nil and name ~= existing.credentialName then
    local status = tables.update_entry(device, "credentials", credential_args.credentialIndex, { credentialName = name })
    if status ~= consts.COMMAND_RESULT.SUCCESS then return status end
  end
  return consts.COMMAND_RESULT.SUCCESS, existing.userIndex
end

-- Per command: update the tables after the lock confirmed a set-credential command we sent.
-- Returns the command result status, or nil for any other command, plus the affected userIndex.
-- For addCredential, a userIndex of 0 creates a new user (its index is chosen here); otherwise the credential
-- is attached to the existing user with that index.
function lock_utils.apply_commanded_credential(device, command_in_progress, credential_args)
  if command_in_progress == consts.LOCK_CREDENTIALS.ADD then
    local user_index = credential_args.userIndex
    if (user_index == 0) then user_index = tables.next_index(device, "users") end
    local user_not_found = not tables.find_entry(device, "users", user_index)
    local status = lock_utils.add_credential_and_user(device, {
      userIndex       = user_index,
      credentialIndex = credential_args.credentialIndex,
      credentialType  = credential_args.credentialType,
      credentialName  = credential_args.credentialName,
    }, user_not_found)
    return status, status == consts.COMMAND_RESULT.SUCCESS and user_index or nil
  elseif command_in_progress == consts.LOCK_CREDENTIALS.UPDATE then
    return lock_utils.update_commanded_credential(device, credential_args)
  end
end

-- Per report: ensure a user and PIN credential exist for a code the lock reports at `credential_index`
-- without any command from us (sync, or a programming event). If a credential already exists there it
-- is left in place. A master report creates a master code user.
function lock_utils.add_reported_credential(device, credential_index, is_master)
  if tables.find_entry(device, "credentials", credential_index) then return end
  return lock_utils.add_credential_and_user(device, {
    userIndex       = tables.next_index(device, "users"),
    credentialIndex = credential_index,
    userType        = is_master and consts.MASTER.USER_TYPE or nil,
  }, true)
end

-- Whether the user at `user_index` is a master code user.
function lock_utils.is_master_user(device, user_index)
  local user = tables.find_entry(device, "users", user_index)
  return user ~= nil and user.userType == consts.MASTER.USER_TYPE
end

function lock_utils.update_entries_to_master(device, credential)
  -- If the credential name is the default guest name, update it to the default master code name.
  if credential.credentialName == "Guest " .. credential.credentialIndex then
    tables.update_entry(device, "credentials", credential.credentialIndex, { credentialName = consts.MASTER.DEFAULT_NAME })
  end

  local user = tables.find_entry(device, "users", credential.userIndex)
  if not user or user.userType ~= "guest" then return end

  -- update userType
  local user_updates = { userType = consts.MASTER.USER_TYPE }
  -- If the user name is the default guest name, update it to the master code name as well.
  if user.userName == "Guest " .. user.userIndex then
    user_updates.userName = consts.MASTER.DEFAULT_NAME
  end
  tables.update_entry(device, "users", user.userIndex, user_updates)
end

-- Delete every credential whose user is not a master code user. Returns the command result status.
function lock_utils.delete_all_non_master_credentials(device)
  return tables.delete_entries_except(device, "credentials", function(cred)
    return lock_utils.is_master_user(device, cred.userIndex)
  end)
end

-- Delete every user that is not a master code user. Returns the command result status.
function lock_utils.delete_all_non_master_users(device)
  return tables.delete_entries_except(device, "users", function(user)
    return user.userType == consts.MASTER.USER_TYPE
  end)
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

return lock_utils
