-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local socket = require "cosock.socket"

local clusters     = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local consts     = require "lock_utils.constants"
local lock_utils = require "lock_utils.utils"
local tables     = require "lock_utils.tables"

local ZigbeeHandlers = {}


-- [[ DOOR LOCK CLUSTER COMMAND RESPONSES ]] --

function ZigbeeHandlers.set_pin_code_response(driver, device, zb_rx)
  -- cached values from capability command
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  local credential_args_in_use = device:get_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE)
  -- zb response values
  local set_pin_code_status = zb_rx.body.zcl_body.status.value

  local SetCodeStatus = clusters.DoorLock.types.DrlkSetCodeStatus
  -- SUCCESS = 0
  -- GENERAL_FAILURE = 1
  -- MEMORY_FULL = 2
  -- DUPLICATE_CODE = 3

  -- mapped failures states
  local RESPONSE_RESULT_MAP = {
    [SetCodeStatus.GENERAL_FAILURE] = consts.COMMAND_RESULT.FAILURE,
    [SetCodeStatus.MEMORY_FULL] = consts.COMMAND_RESULT.RESOURCE_EXHAUSTED,
    [SetCodeStatus.DUPLICATE_CODE] = consts.COMMAND_RESULT.DUPLICATE,
  }

  -- apply result based on response and identify command result status
  local result_status
  if set_pin_code_status == SetCodeStatus.SUCCESS then
    if command_in_progress == consts.LOCK_CREDENTIALS.ADD then
      tables.add_entry(device, "users", {
        userIndex = credential_args_in_use.userIndex,
        userName = "Guest " .. credential_args_in_use.userIndex, -- default
        userType = "guest", -- default
      })
      result_status = tables.add_entry(device, "credentials", {
        userIndex       = credential_args_in_use.userIndex,
        credentialIndex = credential_args_in_use.credentialIndex,
        credentialType  = credential_args_in_use.credentialType,
        credentialName  = "Guest " .. credential_args_in_use.userIndex, -- default
      })
    elseif command_in_progress == consts.LOCK_CREDENTIALS.UPDATE then
      result_status = consts.COMMAND_RESULT.SUCCESS
    end
  elseif RESPONSE_RESULT_MAP[set_pin_code_status] then
    result_status = RESPONSE_RESULT_MAP[set_pin_code_status]
  else
    result_status = consts.COMMAND_RESULT.FAILURE
  end

  -- emit command result
  if command_in_progress then
    local additional_info = result_status == consts.COMMAND_RESULT.SUCCESS and {
      userIndex       = credential_args_in_use.userIndex,
      credentialIndex = credential_args_in_use.credentialIndex,
    } or nil
    lock_utils.emit_command_result(device, capabilities.lockCredentials, command_in_progress, result_status, additional_info)
    lock_utils.clear_busy_state(device)
  end
end


function ZigbeeHandlers.clear_all_pin_codes_response(driver, device, zb_rx)
  -- cached values from capability command
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  -- zb response values
  local clear_pin_code_status = zb_rx.body.zcl_body.status.value

  local ResponseStatus = clusters.DoorLock.types.DrlkPassFailStatus
  -- PASS = 0
  -- FAIL = 1

  -- apply result and identify command result statuses
  local user_status, credential_status
  if clear_pin_code_status == ResponseStatus.PASS then
    -- Only clear the users table when this response is for a deleteAllUsers flow.
    if command_in_progress == consts.LOCK_USERS.DELETE_ALL then
      user_status = tables.delete_all_entries(device, "users")
    end
    credential_status = tables.delete_all_entries(device, "credentials")
  elseif clear_pin_code_status == ResponseStatus.FAIL then
    user_status = consts.COMMAND_RESULT.FAILURE
    credential_status = consts.COMMAND_RESULT.FAILURE
  end

  -- emit command results
  if command_in_progress == consts.LOCK_USERS.DELETE_ALL then
    -- deleteAllUsers injects deleteAllCredentials, so both command results should be emitted.
    lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.DELETE_ALL, user_status)
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE_ALL, credential_status)
  elseif command_in_progress == consts.LOCK_CREDENTIALS.DELETE_ALL then
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE_ALL, credential_status)
  end
  lock_utils.clear_busy_state(device)
end


function ZigbeeHandlers.clear_pin_code_response(driver, device, zb_rx)
  -- cached values from capability command
  local credential_args_in_use = device:get_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE)
  local command_in_progress    = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  -- guard: avoid nil errors if the programming event failsafe already handled this command and cleared the busy state
  if not credential_args_in_use then return end

  -- zb response values
  local clear_pin_code_status = zb_rx.body.zcl_body.status.value

  local ResponseStatus = clusters.DoorLock.types.DrlkPassFailStatus
  -- PASS = 0
  -- FAIL = 1

  -- apply result and identify command result statuses
  local user_status, credential_status
  if clear_pin_code_status == ResponseStatus.PASS then
    credential_status = tables.delete_entry(device, "credentials", credential_args_in_use.credentialIndex)
    if command_in_progress == consts.LOCK_USERS.DELETE or tables.find_entry_by(device, "credentials", "userIndex", credential_args_in_use.userIndex) == nil then
      user_status = tables.delete_entry(device, "users", credential_args_in_use.userIndex)
    end
  elseif clear_pin_code_status == ResponseStatus.FAIL then
    user_status = consts.COMMAND_RESULT.FAILURE
    credential_status = consts.COMMAND_RESULT.FAILURE
  end

  -- emit command results
  if command_in_progress == consts.LOCK_USERS.DELETE then
    -- the deleteUser command injects a deleteCredential command, so both command results should be emitted in this case.
    local user_info = user_status == consts.COMMAND_RESULT.SUCCESS and { userIndex = credential_args_in_use.userIndex } or nil
    local cred_info = credential_status == consts.COMMAND_RESULT.SUCCESS and { credentialIndex = credential_args_in_use.credentialIndex, userIndex = credential_args_in_use.userIndex } or nil
    lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.DELETE, user_status, user_info)
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE, credential_status, cred_info)
  elseif command_in_progress == consts.LOCK_CREDENTIALS.DELETE then
    local cred_info = credential_status == consts.COMMAND_RESULT.SUCCESS and { credentialIndex = credential_args_in_use.credentialIndex, userIndex = credential_args_in_use.userIndex } or nil
    lock_utils.emit_command_result(device, capabilities.lockCredentials, consts.LOCK_CREDENTIALS.DELETE, credential_status, cred_info)
  end
  lock_utils.clear_busy_state(device)
end


function ZigbeeHandlers.get_pin_code_response(driver, device, zb_rx)
  -- cached values from capability command
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  -- zb response values
  local user_id = tonumber(zb_rx.body.zcl_body.user_id.value)

  if command_in_progress == consts.SYNC.CODES_FROM_LOCK then
    -- Only add entries for slots that are actually occupied on the lock.
    local user_status = zb_rx.body.zcl_body.user_status.value
    if user_status == clusters.DoorLock.types.DrlkUserStatus.OCCUPIED_ENABLED then
      -- If an entry already exists at this index, this will be a no-op.
      tables.add_entry(device, "users", {
        userIndex = user_id,
        userName = "Guest " .. user_id,
        userType = "guest",
      })
      tables.add_entry(device, "credentials", {
        userIndex = user_id,
        credentialIndex = user_id,
        credentialType = consts.CRED_TYPE_PIN,
        credentialName = "Guest " .. user_id,
      })
    end
    if user_id >= tables.get_max_entries(device, "credentials") then
      device:set_field(consts.SYNC.CODE_INDEX, nil)
      lock_utils.clear_busy_state(device)
    else
      local synced_code_index = device:get_field(consts.SYNC.CODE_INDEX) + 1
      device:set_field(consts.SYNC.CODE_INDEX, synced_code_index)
      lock_utils.set_busy_state(device, consts.SYNC.CODES_FROM_LOCK, { checkingCode = synced_code_index })
      device:send(clusters.DoorLock.server.commands.GetPINCode(device, synced_code_index))
    end
  end
end


-- [[ DOOR LOCK CLUSTER EVENT NOTIFICATIONS ]] --

function ZigbeeHandlers.programming_event_notification(driver, device, zb_rx)
  -- zb response values
  local user_id = tonumber(zb_rx.body.zcl_body.user_id.value)
  local event_code = tonumber(zb_rx.body.zcl_body.program_event_code.value)

  if device:get_manufacturer() == "ASSA ABLOY iRevo" or device:get_manufacturer() == "Yale" then
    if user_id >= 256 then -- Index is incorrectly written on these devices. Attempt to shift it to get an actual value
      user_id = user_id >> 8
    end
  end

  local ProgramEventCode = clusters.DoorLock.types.ProgramEventCode
  -- MASTER_CODE_CHANGED = 1
  -- PIN_CODE_ADDED = 2
  -- PIN_CODE_DELETED = 3
  -- PIN_CODE_CHANGED = 4
  -- RFID_CODE_ADDED = 5
  -- RFID_CODE_DELETED = 6


  -- failsafes: handle the case where we receive a programming event notification for a command we've just sent,
  -- which can be verified by checking that the user id matches the one used in the command, but before we receive
  -- the response for that command. This gives us double the chance to handle the command
  -- in case the response handler doesn't execute properly for some reason.
  --
  -- cached values from capability command, if applicable.
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  local credential_args_in_use = device:get_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE) or {}
  if command_in_progress and credential_args_in_use.credentialIndex == user_id then
    local result_status
    if event_code == ProgramEventCode.PIN_CODE_ADDED then
      if command_in_progress == consts.LOCK_CREDENTIALS.ADD then
        tables.add_entry(device, "users", {
          userIndex = credential_args_in_use.userIndex,
          userName = "Guest " .. credential_args_in_use.userIndex, -- default
          userType = "guest", -- default
        })
        result_status = tables.add_entry(device, "credentials", {
          userIndex       = credential_args_in_use.userIndex,
          credentialIndex = credential_args_in_use.credentialIndex,
          credentialType  = credential_args_in_use.credentialType,
          credentialName  = credential_args_in_use.credentialName, -- optional
        })
      elseif command_in_progress == consts.LOCK_CREDENTIALS.UPDATE then
        -- some devices emit PIN_CODE_ADDED even for UPDATE events
        result_status = consts.COMMAND_RESULT.SUCCESS
      end
    elseif event_code == ProgramEventCode.PIN_CODE_DELETED and (command_in_progress == consts.LOCK_CREDENTIALS.DELETE or command_in_progress == consts.LOCK_USERS.DELETE) then
      result_status = tables.delete_entry(device, "credentials", credential_args_in_use.credentialIndex)
      -- the deleteUser command injects a deleteCredential command, so ensure the lockUsers command results is emitted in this case.
      if command_in_progress == consts.LOCK_USERS.DELETE or tables.find_entry_by(device, "credentials", "userIndex", credential_args_in_use.userIndex) == nil then
        local user_status = tables.delete_entry(device, "users", credential_args_in_use.userIndex)
        local user_info = user_status == consts.COMMAND_RESULT.SUCCESS and { userIndex = credential_args_in_use.userIndex } or nil
        if command_in_progress == consts.LOCK_USERS.DELETE then
          lock_utils.emit_command_result(device, capabilities.lockUsers, consts.LOCK_USERS.DELETE, user_status, user_info)
          command_in_progress = consts.LOCK_CREDENTIALS.DELETE -- ensure the lockCredentials result is emitted after this with the correct command context
        end
      end
    elseif event_code == ProgramEventCode.PIN_CODE_CHANGED and command_in_progress == consts.LOCK_CREDENTIALS.UPDATE then
      result_status = consts.COMMAND_RESULT.SUCCESS
    end

    if result_status then
      lock_utils.emit_command_result(device,
        capabilities.lockCredentials,
        command_in_progress,
        result_status,
        { userIndex = credential_args_in_use.userIndex, credentialIndex = credential_args_in_use.credentialIndex }
      )
      lock_utils.clear_busy_state(device)
      return
    end
  end

  -- handle the case where we receive a programming event notification for a code we've just deleted,
  if event_code == ProgramEventCode.PIN_CODE_ADDED then
    -- if no "addCredential" command is in progress, check if the credential is already stored locally.
    local credential = tables.find_entry(device, "credentials", user_id)
    if not credential then
      -- check what user slot we have to associate this with and add a default user
      local next_index = tables.next_index(device, "users")
      if next_index and next_index <= tables.get_max_entries(device, "users") then
        tables.add_entry(device, "users", {
          userIndex = next_index,
          userName = "Guest " .. next_index,
          userType = "guest",
        })
        tables.add_entry(device, "credentials", {
          userIndex = next_index,
          credentialIndex = user_id,
          credentialType = consts.CRED_TYPE_PIN,
          credentialName = "Guest " .. next_index,
        })
      end
    end
  elseif event_code == ProgramEventCode.PIN_CODE_DELETED then
    -- check if a credential exists locally for this user id, then
    -- try to delete the entries in our tables corresponding to this code.
    local credential = tables.find_entry(device, "credentials", user_id)
    if credential then
      tables.delete_entry(device, "credentials", user_id)
      -- Only delete the user if they have no remaining credentials
      if tables.find_entry_by(device, "credentials", "userIndex", credential.userIndex) == nil then
        tables.delete_entry(device, "users", credential.userIndex)
      end
    end
  end
end

function ZigbeeHandlers.operating_event_notification(driver, device, zb_rx)
  local op_event_code = tonumber(zb_rx.body.zcl_body.operation_event_code.value)
  local op_event_source = tonumber(zb_rx.body.zcl_body.operation_event_source.value)
  local user_id = tonumber(zb_rx.body.zcl_body.user_id.value)

  -- get lock event or return
  local OpEventCode = clusters.DoorLock.types.OperationEventCode
  local OP_EVENT_CODE_CAPABILITY_MAP = {
    [OpEventCode.LOCK]            = capabilities.lock.lock.locked(),
    [OpEventCode.UNLOCK]          = capabilities.lock.lock.unlocked(),
    [OpEventCode.ONE_TOUCH_LOCK]  = capabilities.lock.lock.locked(),
    [OpEventCode.KEY_LOCK]        = capabilities.lock.lock.locked(),
    [OpEventCode.KEY_UNLOCK]      = capabilities.lock.lock.unlocked(),
    [OpEventCode.AUTO_LOCK]       = capabilities.lock.lock.locked(),
    [OpEventCode.MANUAL_LOCK]     = capabilities.lock.lock.locked(),
    [OpEventCode.MANUAL_UNLOCK]   = capabilities.lock.lock.unlocked(),
    [OpEventCode.SCHEDULE_LOCK]   = capabilities.lock.lock.locked(),
    [OpEventCode.SCHEDULE_UNLOCK] = capabilities.lock.lock.unlocked()
  }
  local lock_event = OP_EVENT_CODE_CAPABILITY_MAP[op_event_code]
  if not lock_event then return end
  lock_event.data = {}

  -- get method of lock event
  local OpEventSource = clusters.DoorLock.types.DrlkOperationEventSource
  local OP_EVENT_SOURCE_CAPABILITY_MAP = {
    [OpEventSource.KEYPAD] = "keypad",
    [OpEventSource.RF]     = "command",
    [OpEventSource.MANUAL] = "manual",
    [OpEventSource.RFID]   = "rfid",
  }
  if op_event_code == OpEventCode.AUTO_LOCK or
    op_event_code == OpEventCode.SCHEDULE_LOCK or
    op_event_code == OpEventCode.SCHEDULE_UNLOCK
  then
    lock_event.data.method = "auto"
  else
    lock_event.data.method = OP_EVENT_SOURCE_CAPABILITY_MAP[op_event_source] or "manual"
  end

  -- get stored lockUsers data if applicable
  if op_event_source == OpEventSource.KEYPAD and device:supports_capability(capabilities.lockUsers) then
    local credential = tables.find_entry(device, "credentials", user_id)
    local associated_user = credential and tables.find_entry_by(device, "users", "userIndex", credential.userIndex) or nil
    if associated_user then
      lock_event.data.userIndex = associated_user.userIndex
      lock_event.data.userName = associated_user.userName
      lock_event.data.userType = associated_user.userType
    else
      lock_event.data.userIndex = user_id
      lock_event.data.userName = "Guest " .. user_id -- default
    end
  end

  -- if this is an event corresponding to a recently-received attribute report, we
  -- want to set our delay timer for future lock attribute report events
  local endpoint_id = zb_rx.address_header.src_endpoint.value
  if lock_event.value.value == device:get_latest_state(
    device:get_component_id_for_endpoint(endpoint_id),
    capabilities.lock.ID,
    capabilities.lock.lock.ID
  ) then
    local preceding_event_time = device:get_field(consts.DELAY_LOCK_EVENT) or 0
    local time_diff = socket.gettime() - preceding_event_time
    if time_diff < consts.MAX_DELAY then
      device:set_field(consts.DELAY_LOCK_EVENT, time_diff)
    end
  end

  device:emit_event_for_endpoint(endpoint_id, lock_event)
end


-- [[ DOOR LOCK CLUSTER ATTRIBUTES ]] --

function ZigbeeHandlers.lock_state(driver, device, value, zb_rx)
  local attr = capabilities.lock.lock
  local LOCK_STATE = {
    [value.NOT_FULLY_LOCKED]     = attr.unknown(),
    [value.LOCKED]               = attr.locked(),
    [value.UNLOCKED]             = attr.unlocked(),
    [value.UNDEFINED]            = attr.unknown(),
  }

  -- this is where we decide whether or not we need to delay our lock event because we've
  -- observed it coming before the event (or we're starting to compute the timer)
  local delay = device:get_field(consts.DELAY_LOCK_EVENT) or 100
  if (delay < consts.MAX_DELAY) then
    device.thread:call_with_delay(delay+.5, function ()
      device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, LOCK_STATE[value.value] or attr.unknown())
    end)
  else
    device:set_field(consts.DELAY_LOCK_EVENT, socket.gettime())
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, LOCK_STATE[value.value] or attr.unknown())
  end
end

function ZigbeeHandlers.max_pin_code_length(driver, device, value)
  device:emit_event(capabilities.lockCredentials.maxPinCodeLen(value.value, { visibility = { displayed = false } }))
end

function ZigbeeHandlers.min_pin_code_length(driver, device, value)
  device:emit_event(capabilities.lockCredentials.minPinCodeLen(value.value, { visibility = { displayed = false } }))
end

function ZigbeeHandlers.number_of_pin_users_supported(driver, device, value)
  if not device:supports_capability_by_id(capabilities.lockCodes.ID) and value.value > 0 then
    -- this device was generically fingerprinted, but supports PIN users, so we should migrate it.
    device:try_update_metadata({ profile = "base-lock" })
  end
  if device:supports_capability(capabilities.lockCredentials) then
    device:emit_event(capabilities.lockCredentials.pinUsersSupported(value.value, {visibility = {displayed = false}}))
  end
  if device:supports_capability(capabilities.lockUsers) then
    device:emit_event(capabilities.lockUsers.totalUsersSupported(value.value, {visibility = {displayed = false}}))
  end
end


-- [[ ALARMS CLUSTER COMMANDS ]] --

function ZigbeeHandlers.alarm(driver, device, zb_rx)
  local ALARM_REPORT = {
    [0] = capabilities.lock.lock.unknown(),
    [1] = capabilities.lock.lock.unknown(),
    -- Events 16-19 are low battery events, but are presented as descriptionText only
  }
  if (ALARM_REPORT[zb_rx.body.zcl_body.alarm_code.value] ~= nil) then
    device:emit_event(ALARM_REPORT[zb_rx.body.zcl_body.alarm_code.value])
  end
end


return ZigbeeHandlers
