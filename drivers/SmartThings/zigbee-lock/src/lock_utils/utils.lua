-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

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
  local clusters = require "st.zigbee.zcl.clusters"
  -- Per spec, this attribute should be a boolean set to True if it is ok for the door lock server to send PINs over the air.
  device:send(clusters.DoorLock.attributes.SendPINOverTheAir:write(device, true))

  -- if consts.SYNC.CODE_INDEX is nil, we haven't started syncing codes from the lock yet, so start the process from 0.
  if (device:get_field(consts.SYNC.CODE_INDEX) == nil) then
    device:set_field(consts.SYNC.CODE_INDEX, 0)
  end
  lock_utils.set_busy_state(device, consts.SYNC.CODES_FROM_LOCK)
  device:send(clusters.DoorLock.server.commands.GetPINCode(device, device:get_field(consts.SYNC.CODE_INDEX)))
end

-- Yale locks hold a master code at credential index 0. Keep it represented locally at all times, so that the slot is
-- never handed out as the next available credential index.
function lock_utils.ensure_yale_master_code(device)
  if lock_utils.is_yale(device) then
    lock_utils.add_reported_credential(device, consts.YALE_MASTER_CODE_SLOT, true)
  end
end

-- [[ CREDENTIAL TABLE MANAGEMENT ]] --

-- Add a user and its credential together. Shared by the commanded and reported paths below. Existing entries at
-- either index are left untouched by the underlying table add. Returns the result status of the credential add.
function lock_utils.add_user_and_credential(device, args)
  local tables = require "lock_utils.tables"
  local user_type = args.userType or "guest"
  local name = (user_type == consts.USER_TYPE_MASTER) and consts.MASTER_CODE_NAME or ("Guest " .. args.userIndex)
  tables.add_entry(device, "users", {
    userIndex = args.userIndex,
    userName  = name,
    userType  = user_type,
  })
  return tables.add_entry(device, "credentials", {
    userIndex       = args.userIndex,
    credentialIndex = args.credentialIndex,
    credentialType  = args.credentialType or consts.CRED_TYPE_PIN,
    credentialName  = args.credentialName or name,
  })
end

-- Per command: update the tables after the lock confirmed a set-credential command we sent.
-- Returns the command result status, or nil for any other command.
function lock_utils.add_commanded_credential(device, command_in_progress, credential_args)
  if command_in_progress == consts.LOCK_CREDENTIALS.ADD then
    return lock_utils.add_user_and_credential(device, credential_args)
  elseif command_in_progress == consts.LOCK_CREDENTIALS.UPDATE then
    return consts.COMMAND_RESULT.SUCCESS
  end
end

-- Per report: add a user and PIN credential for a code the lock reports at `credential_index` without any command
-- from us (sync, or a programming event), unless a credential already exists there.
function lock_utils.add_reported_credential(device, credential_index, is_master)
  local tables = require "lock_utils.tables"
  if tables.find_entry(device, "credentials", credential_index) then return end
  local user_index = tables.next_index(device, "users")
  if user_index > tables.get_max_entries(device, "users") then
    device.log.warn(string.format("no free user slot for the code at credential index %d", credential_index))
    return
  end
  lock_utils.add_user_and_credential(device, {
    userIndex       = user_index,
    credentialIndex = credential_index,
    userType        = is_master and consts.USER_TYPE_MASTER or nil,
  })
end

-- Whether this device is a Yale or ASSA ABLOY iRevo lock.
function lock_utils.is_yale(device)
  local manufacturer = device:get_manufacturer()
  return manufacturer == "Yale" or manufacturer == "ASSA ABLOY iRevo"
end

-- Whether the user at `user_index` is a master code user.
function lock_utils.is_master_user(device, user_index)
  local tables = require "lock_utils.tables"
  local user = tables.find_entry(device, "users", user_index)
  return user ~= nil and user.userType == consts.USER_TYPE_MASTER
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
