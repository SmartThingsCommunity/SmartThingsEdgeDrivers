-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local consts = require "lock_utils.constants"
local tables = require "lock_utils.tables"
--- @type st.zwave.CommandClass.UserCode
local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })

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


-- True if a deleteCredential or deleteUser of the credential at credential_index is waiting on the lock.
function lock_utils.is_delete_in_progress(device, credential_index)
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  local credential_args = device:get_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE) or {}
  return (command_in_progress == consts.LOCK_CREDENTIALS.DELETE or command_in_progress == consts.LOCK_USERS.DELETE) and
    credential_args.credentialIndex == credential_index
end

-- Report a delete the lock refused, leaving the user and credential in place.
function lock_utils.emit_delete_failure(device)
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  if command_in_progress == consts.LOCK_USERS.DELETE then
    lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.DELETE, consts.COMMAND_RESULT.FAILURE)
  end
  lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE, consts.COMMAND_RESULT.FAILURE)
  lock_utils.clear_busy_state(device)
end


-- [[ SYNC STATE MANAGEMENT ]] --

function lock_utils.sync_device_state(device)
  -- skip if unsupported, already synced, or busy (including a sync already in progress).
  if not (device:supports_capability(capabilities.lockCredentials) and
    device:get_field(consts.SYNC.CODES_SYNCED) ~= consts.SYNC.CODES_SYNC_VERSION and
    not lock_utils.is_device_busy(device)) then
    return
  end

  -- a persisted index from a sync begun under a different sync version is stale; start over.
  if device:get_field(consts.SYNC.CODE_INDEX_VERSION) ~= consts.SYNC.CODES_SYNC_VERSION then
    device:set_field(consts.SYNC.CODE_INDEX, nil, { persist = true })
  end

  -- if consts.SYNC.CODE_INDEX is nil, we haven't started syncing codes from the lock yet, so start the
  -- process from the first valid index. Persist the index so we can resume after a restart as needed.
  if (device:get_field(consts.SYNC.CODE_INDEX) == nil) then
    device:set_field(consts.SYNC.CODE_INDEX, tables.get_minimum(device, "credentials"), { persist = true })
    device:set_field(consts.SYNC.CODE_INDEX_VERSION, consts.SYNC.CODES_SYNC_VERSION, { persist = true })
  end
  lock_utils.set_busy_state(device, consts.SYNC.CODES_FROM_LOCK)
  device:send(UserCode:Get({user_identifier = device:get_field(consts.SYNC.CODE_INDEX)}))
end

-- Emit the spec default PIN length range (4-10) if no min/max has been reported yet.
-- Migrated devices copy theirs from lockCodes, so those are left alone to avoid
-- clobbering/misinterpreting them. Schlage locks report their own length later via a
-- configuration parameter, which overrides these defaults.
function lock_utils.ensure_pin_length_bounds(device)
  if not device:supports_capability(capabilities.lockCredentials) then
    return
  end
  if device:get_latest_state("main", capabilities.lockCredentials.ID, capabilities.lockCredentials.minPinCodeLen.NAME) == nil then
    device:emit_event(capabilities.lockCredentials.minPinCodeLen(consts.DEFAULT_MIN_PIN_LENGTH,
      { visibility = { displayed = false } }))
  end
  if device:get_latest_state("main", capabilities.lockCredentials.ID, capabilities.lockCredentials.maxPinCodeLen.NAME) == nil then
    device:emit_event(capabilities.lockCredentials.maxPinCodeLen(consts.DEFAULT_MAX_PIN_LENGTH,
      { visibility = { displayed = false } }))
  end
end

-- Advance the sync-codes-from-lock flow after a report for the current code index (consts.SYNC.CODE_INDEX).
-- `occupied` is true when the lock reported an occupied slot at that index; `available` is true only when
-- it explicitly reported the slot as available. Any other status (reserved, disabled, unknown) neither
-- resets nor advances the consecutive-unoccupied counter, so it can't end the sync early.
function lock_utils.continue_code_sync(device, occupied, available)
  local code_index = device:get_field(consts.SYNC.CODE_INDEX)
  if code_index == nil then return end

  if occupied then
    lock_utils.add_reported_credential(device, code_index)
    -- reset the consecutive unoccupied codes counter since we found an occupied code
    device:set_field(consts.SYNC.CONSECUTIVE_UNOCCUPIED_CODES, 0)
  elseif available then
    device:set_field(consts.SYNC.CONSECUTIVE_UNOCCUPIED_CODES, (device:get_field(consts.SYNC.CONSECUTIVE_UNOCCUPIED_CODES) or 0) + 1)
  end

  if code_index >= tables.get_max_entries(device, "credentials") or
   (device:get_field(consts.SYNC.CONSECUTIVE_UNOCCUPIED_CODES) or 0) > 5 then
    -- stop if we hit the max number of codes supported by the lock, or if we have received 5 consecutive unoccupied codes.
    device:set_field(consts.SYNC.CODE_INDEX, nil, { persist = true })
    device:set_field(consts.SYNC.CONSECUTIVE_UNOCCUPIED_CODES, nil)
    device:set_field(consts.SYNC.CODES_SYNCED, consts.SYNC.CODES_SYNC_VERSION, { persist = true })
    lock_utils.clear_busy_state(device)
  else
    local next_index = code_index + 1
    device:set_field(consts.SYNC.CODE_INDEX, next_index, { persist = true })
    lock_utils.set_busy_state(device, consts.SYNC.CODES_FROM_LOCK)
    device:send(UserCode:Get({user_identifier = next_index}))
  end
end


-- [[ PROGRAMMING CODE MANAGEMENT ]] --
--
-- The programming code credential is found with tables.get_programming_credential.

-- Whether the user at user_index is a programming user.
function lock_utils.is_programming_user(device, user_index)
  local user = tables.find_entry(device, "users", user_index)
  return user ~= nil and user.userType == consts.PROGRAMMING_USER.USER_TYPE
end

-- Clear every entry of the "users" or "credentials" table except the programming code credential and its user.
function lock_utils.delete_all_non_programming_entries(device, table_name)
  local programming = tables.get_programming_credential(device)
  local match_key = table_name == "users" and "userIndex" or "credentialIndex"
  tables.delete_all_entries(device, table_name, function(entry)
    return programming ~= nil and entry[match_key] == programming[match_key]
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


-- [[ HELPERS ]] --

-- True if a User Code Report shows a code in the slot. A lock that does not report the status of a slot
-- still holds a code if it reports one.
function lock_utils.is_code_occupied(cmd)
  return cmd.args.user_id_status == UserCode.user_id_status.ENABLED_GRANT_ACCESS or
    (cmd.args.user_id_status == UserCode.user_id_status.STATUS_NOT_AVAILABLE and cmd.args.user_code ~= nil)
end

function lock_utils.get_code_id_from_notification_event(event_params, v1_alarm_level)
  local code_id = v1_alarm_level
  if event_params ~= nil and event_params ~= "" then
    event_params = {event_params:byte(1,-1)}
    code_id = (#event_params == 1) and event_params[1] or event_params[3]
  end
  return tostring(code_id)
end


-- [[ CREDENTIAL TABLE MANAGEMENT ]] --

-- Add a credential and, optionally, a new user for it. `args.userIndex` is the credential's user.
-- When `add_user` is true the user is created too, so a user never exists without a credential; when false
-- the credential is attached to the already-existing user `args.userIndex`.
-- The credential is added first; the user is only added if that succeeded, so a failed or
-- colliding credential add leaves no user behind. Returns the result status of the credential add.
function lock_utils.add_credential_and_user(device, args, add_user)
  local name = "Guest " .. args.userIndex
  local credential_status = tables.add_entry(device, "credentials", {
    userIndex       = args.userIndex,
    credentialIndex = args.credentialIndex,
    credentialType  = args.credentialType or consts.CRED_TYPE_PIN,
    credentialName  = args.credentialName or name,
  })
  if add_user and credential_status == consts.COMMAND_RESULT.SUCCESS then
    tables.add_entry(device, "users", {
      userIndex = args.userIndex,
      userName  = args.credentialName or name,
      userType  = "guest",
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
    if user_index == 0 then user_index = tables.next_index(device, "users") end
    -- also covers a requested user that was deleted while the lock was confirming the code
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
-- without any command from us (sync, or a user code event). If a credential already exists there it
-- is left in place.
function lock_utils.add_reported_credential(device, credential_index)
  -- Index 0 means "all users" in Z-Wave, so a report for it is not a credential.
  if credential_index < tables.get_minimum(device, "credentials") then return end
  if tables.find_entry(device, "credentials", credential_index) then return end
  return lock_utils.add_credential_and_user(device, {
    userIndex       = tables.next_index(device, "users"),
    credentialIndex = credential_index,
  }, true)
end

function lock_utils.set_credential_report_helper(device, credential_index)
  -- cached values from capability command
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  local credential_args = device:get_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE) or {}

  local result_status, user_index = lock_utils.apply_commanded_credential(device, command_in_progress, credential_args)
  if result_status then
    local additional_info = result_status == consts.COMMAND_RESULT.SUCCESS and {
      userIndex       = user_index,
      credentialIndex = credential_args.credentialIndex,
    } or nil
    lock_utils.emit_command_result(device, capabilities.lockCredentials, command_in_progress, result_status, additional_info)
    lock_utils.clear_busy_state(device)
  else
    -- no add/update command in progress, therefore the credential was added out-of-band
    lock_utils.add_reported_credential(device, credential_index)
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
