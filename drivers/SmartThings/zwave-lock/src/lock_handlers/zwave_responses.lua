-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local socket = require "cosock.socket"

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
--- @type st.zwave.CommandClass.UserCode
local UserCode = (require "st.zwave.CommandClass.UserCode")({version=1})
local TamperDefaults = require "st.zwave.defaults.tamperAlert"

local consts     = require "lock_utils.constants"
local lock_utils = require "lock_utils.utils"
local tables     = require "lock_utils.tables"


local ZwaveHandlers = {}


-- [[ USER CODE COMMAND CLASS ]]

function ZwaveHandlers.user_code_report(driver, device, cmd)
  -- zw report values
  local credential_index = cmd.args.user_identifier
  local user_id_status = cmd.args.user_id_status

  -- cached values from capability command
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)

  -- Determine boolean states of user code slot
  local user_code_occupied = user_id_status == UserCode.user_id_status.ENABLED_GRANT_ACCESS or
    (user_id_status == UserCode.user_id_status.STATUS_NOT_AVAILABLE and cmd.args.user_code)
  local user_code_available = user_id_status == UserCode.user_id_status.AVAILABLE

  if command_in_progress == consts.SYNC.CODES_FROM_LOCK then
    if user_code_occupied then
      -- If an entry already exists at this index, this will be a no-op.
      tables.add_entry(device, "users", {
        userIndex = credential_index,
        userName = "Guest " .. credential_index,
        userType = "guest",
      })
      tables.add_entry(device, "credentials", {
        userIndex = credential_index,
        credentialIndex = credential_index,
        credentialType = consts.CRED_TYPE_PIN,
        credentialName = "Guest " .. credential_index,
      })
      -- reset the consecutive unoccupied codes counter since we found an occupied code
      device:set_field(consts.SYNC.CONSECUTIVE_UNOCCUPIED_CODES, 0)
    elseif user_code_available then
      local consecutive_unoccupied_codes = (device:get_field(consts.SYNC.CONSECUTIVE_UNOCCUPIED_CODES) or 0) + 1
      device:set_field(consts.SYNC.CONSECUTIVE_UNOCCUPIED_CODES, consecutive_unoccupied_codes)
    end

    -- Sync: continue to next code or finish
    if credential_index >= tables.get_max_entries(device, "credentials") or
     (device:get_field(consts.SYNC.CONSECUTIVE_UNOCCUPIED_CODES) or 0) > 5 then
      -- stop if we hit the max number of codes supported by the lock, or if we have received 5 consecutive unoccupied codes.
      device:set_field(consts.SYNC.CODE_INDEX, nil)
      lock_utils.clear_busy_state(device)
    else
      local synced_code_index = device:get_field(consts.SYNC.CODE_INDEX) + 1
      device:set_field(consts.SYNC.CODE_INDEX, synced_code_index)
      lock_utils.set_busy_state(device, consts.SYNC.CODES_FROM_LOCK, { checkingCode = synced_code_index })
      device:send(UserCode:Get({user_identifier = synced_code_index}))
    end
    return
  elseif user_code_occupied then
      -- Code slot is now occupied: add or update credential and associated user
      lock_utils.set_credential_report_helper(device, credential_index)
  elseif user_code_available then
    if command_in_progress == consts.LOCK_CREDENTIALS.ADD then
      lock_utils.emit_command_result(device, capabilities.lockCredentials,
        consts.LOCK_CREDENTIALS.ADD, consts.COMMAND_RESULT.FAILURE)
      lock_utils.clear_busy_state(device)
    elseif command_in_progress == consts.LOCK_CREDENTIALS.DELETE or tables.find_entry(device, "credentials", credential_index) then
      lock_utils.delete_credential_report_helper(device, credential_index)
    end
  end
end

function ZwaveHandlers.users_number_report(driver, device, cmd)
  device:emit_event(capabilities.lockUsers.totalUsersSupported(
    cmd.args.supported_users, { state_change = true, visibility = { displayed = false } }))
  device:emit_event(capabilities.lockCredentials.pinUsersSupported(
    cmd.args.supported_users, { state_change = true, visibility = { displayed = false } }))
end


-- [[ NOTIFICATION COMMAND CLASS ]] --

function ZwaveHandlers.user_code_event_handler(driver, device, cmd)
  if cmd.args.notification_type ~= Notification.notification_type.ACCESS_CONTROL then
    return
  end
  -- zw event values
  local event = cmd.args.event
  local credential_index = tonumber(lock_utils.get_code_id_from_notification_event(
    cmd.args.event_parameter, cmd.args.v1_alarm_level))
  -- cached value from capability event, if applicable
  local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
  -- This type includes many lock-related events, way too many to list,
  -- including user code changes and door operations
  local access_control_event = Notification.event.access_control

  if event == access_control_event.ALL_USER_CODES_DELETED then
    tables.delete_all_entries(device, "credentials")
    tables.delete_all_entries(device, "users")

  elseif event == access_control_event.SINGLE_USER_CODE_DELETED then
    lock_utils.delete_credential_report_helper(device, credential_index)

  elseif event == access_control_event.NEW_USER_CODE_ADDED then
    lock_utils.set_credential_report_helper(device, credential_index)

  elseif event == access_control_event.NEW_PROGRAM_CODE_ENTERED_UNIQUE_CODE_FOR_LOCK_CONFIGURATION then
    -- aka "master code" changed
    if command_in_progress == consts.LOCK_CREDENTIALS.UPDATE then
      lock_utils.emit_command_result(device, capabilities.lockCredentials,
        consts.LOCK_CREDENTIALS.UPDATE, consts.COMMAND_RESULT.SUCCESS)
      lock_utils.clear_busy_state(device)
    end

  elseif event == access_control_event.NEW_USER_CODE_NOT_ADDED_DUE_TO_DUPLICATE_CODE then
    if command_in_progress then
      lock_utils.emit_command_result(device, capabilities.lockCredentials,
        consts.LOCK_CREDENTIALS.ADD, consts.COMMAND_RESULT.DUPLICATE)
      lock_utils.clear_busy_state(device)
    end
  end
end

function ZwaveHandlers.door_operation_event_handler(driver, device, cmd)
  if cmd.args.notification_type ~= Notification.notification_type.ACCESS_CONTROL then
    return
  end
  -- zw event value
  local event = cmd.args.event
  -- This type includes many lock-related events, way too many to list,
  -- including user code changes and door operations
  local access_control_event = Notification.event.access_control
  -- send lock, unlock, or unknown event based on the event coded
  local capability_event
  if not (event >= access_control_event.MANUAL_LOCK_OPERATION and event <= access_control_event.LOCK_JAMMED) then
    return -- This is the subset of event kinds that we care about for door operation reporting
  elseif ((event >= access_control_event.MANUAL_LOCK_OPERATION and
        event <= access_control_event.KEYPAD_UNLOCK_OPERATION) or
        event == access_control_event.AUTO_LOCK_LOCKED_OPERATION) then
    -- even event codes are unlocks, odd event codes are locks
    local events = {[0] = capabilities.lock.lock.unlocked(), [1] = capabilities.lock.lock.locked()}
    capability_event = events[event & 1]
  elseif (event >= access_control_event.MANUAL_NOT_FULLY_LOCKED_OPERATION and
          event <= access_control_event.LOCK_JAMMED) then
    capability_event = capabilities.lock.lock.unknown()
  else
    return -- no lock event to send for this code
  end

  local access_control_event_capability_map = {
    [access_control_event.MANUAL_UNLOCK_OPERATION] = "manual",
    [access_control_event.MANUAL_LOCK_OPERATION] = "manual",
    [access_control_event.MANUAL_NOT_FULLY_LOCKED_OPERATION] = "manual",
    [access_control_event.RF_LOCK_OPERATION] = "command",
    [access_control_event.RF_UNLOCK_OPERATION] = "command",
    [access_control_event.RF_NOT_FULLY_LOCKED_OPERATION] = "command",
    [access_control_event.KEYPAD_LOCK_OPERATION] = "keypad",
    [access_control_event.KEYPAD_UNLOCK_OPERATION] = "keypad",
    [access_control_event.AUTO_LOCK_LOCKED_OPERATION] = "auto",
    [access_control_event.AUTO_LOCK_NOT_FULLY_LOCKED_OPERATION] = "auto"
  }

  capability_event.data = {}
  capability_event.data.method = access_control_event_capability_map[event]

  if (event == access_control_event.MANUAL_UNLOCK_OPERATION and cmd.args.event_parameter == 2) then
    capability_event.data.method = "keypad" -- some locks can distinguish being manually locked via keypad
  elseif (event == access_control_event.KEYPAD_LOCK_OPERATION or event == access_control_event.KEYPAD_UNLOCK_OPERATION) then
    local code_id = tonumber(lock_utils.get_code_id_from_notification_event(
      cmd.args.event_parameter, cmd.args.v1_alarm_level))    -- Look up stored lockUsers data if applicable
    if device:supports_capability(capabilities.lockUsers) then
      local credential = tables.find_entry(device, "credentials", code_id)
      if credential then
        local user = tables.find_entry(device, "users", credential.userIndex)
        capability_event.data.userIndex = credential.userIndex
        if user then
          capability_event.data.userName = user.userName
          capability_event.data.userType = user.userType
        end
      else
        capability_event.data.userIndex = code_id
      end
    end
  end

  -- Delay timer logic to handle duplicate lock state reports
  if device:get_latest_state(
    "main",
    capabilities.lock.ID,
    capabilities.lock.lock.ID) == capability_event.value.value then
    local preceding_event_time = device:get_field(consts.DELAY_LOCK_EVENT) or 0
    local time_diff = socket.gettime() - preceding_event_time
    if time_diff < consts.MAX_DELAY then
      device:set_field(consts.DELAY_LOCK_EVENT, time_diff)
    end
  end

  local timer = device:get_field(consts.DELAY_LOCK_EVENT_TIMER)
  if timer ~= nil then
    device.thread:cancel_timer(timer)
    device:set_field(consts.DELAY_LOCK_EVENT_TIMER, nil)
  end

  device:emit_event(capability_event)
end

function ZwaveHandlers.notification_report(driver, device, cmd)
  ZwaveHandlers.user_code_event_handler(driver, device, cmd)
  ZwaveHandlers.door_operation_event_handler(driver, device, cmd)
  -- Tamper events handled by default tamper handler
  TamperDefaults.zwave_handlers[cc.NOTIFICATION][Notification.REPORT](driver, device, cmd)
end


-- [[ TIME COMMAND CLASS ]] --

function ZwaveHandlers.time_get_handler(driver, device, cmd)
  local Time = (require "st.zwave.CommandClass.Time")({ version = 1 })
  local time = os.date("*t")
  device:send_to_component(
    Time:Report({
      hour_local_time = time.hour,
      minute_local_time = time.min,
      second_local_time = time.sec
    }),
    device:endpoint_to_component(cmd.src_channel)
  )
end

return ZwaveHandlers
