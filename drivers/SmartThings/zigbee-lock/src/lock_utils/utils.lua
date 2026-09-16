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

  -- if consts.SYNC.CODE_INDEX is nil, we haven't started syncing codes from the lock yet,
  -- so start the process from 1. note: the Zigbee "Master Code" is associated with index 0.
  if (device:get_field(consts.SYNC.CODE_INDEX) == nil) then
    device:set_field(consts.SYNC.CODE_INDEX, 1)
  end
  lock_utils.set_busy_state(device, consts.SYNC.CODES_FROM_LOCK)
  device:send(clusters.DoorLock.server.commands.GetPINCode(device, device:get_field(consts.SYNC.CODE_INDEX)))
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
