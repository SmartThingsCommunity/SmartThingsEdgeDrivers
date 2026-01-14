-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local INITIAL_INDEX = 1

local new_lock_utils = {
  -- Constants
  ADD_CREDENTIAL = "addCredential",
  ADD_USER = "addUser",
  BUSY = "busy",
  COMMAND_NAME = "commandName",
  CREDENTIAL_TYPE = "pin",
  CHECKING_CODE = "checkingCode",
  DELETE_ALL_CREDENTIALS = "deleteAllCredentials",
  DELETE_ALL_USERS = "deleteAllUsers",
  DELETE_CREDENTIAL = "deleteCredential",
  DELETE_USER = "deleteUser",
  LOCK_CREDENTIALS = "lockCredentials",
  LOCK_USERS = "lockUsers",
  ACTIVE_CREDENTIAL = "pendingCredential",
  STATUS_BUSY = "busy",
  STATUS_DUPLICATE = "duplicate",
  STATUS_FAILURE = "failure",
  STATUS_INVALID_COMMAND = "invalidCommand",
  STATUS_OCCUPIED = "occupied",
  STATUS_RESOURCE_EXHAUSTED = "resourceExhausted",
  STATUS_SUCCESS = "success",
  TABLES_LOADED = "tablesLoaded",
  UPDATE_CREDENTIAL = "updateCredential",
  UPDATE_USER = "updateUser",
  USER_INDEX = "userIndex",
  USER_NAME = "userName",
  USER_TYPE = "userType"
}

-- check if we are currently busy performing a task.
-- if we aren't then set as busy.
new_lock_utils.busy_check_and_set = function (device, command, override_busy_check)
  if override_busy_check then
    -- the function was called by an injected command.
    return false
  end

  local c_time = os.time()
  local busy_state = device:get_field(new_lock_utils.BUSY) or false

  if busy_state == false or c_time - busy_state > 10 then
    device:set_field(new_lock_utils.COMMAND_NAME, command)
    device:set_field(new_lock_utils.BUSY, c_time)
    return false
  else
    local command_result_info = {
      commandName = command.name,
      statusCode = new_lock_utils.STATUS_BUSY
    }
    if command.type == new_lock_utils.LOCK_USERS then
      device:emit_event(capabilities.lockUsers.commandResult(
        command_result_info, { state_change = true, visibility = { displayed = true } }
      ))
    else
      device:emit_event(capabilities.lockCredentials.commandResult(
        command_result_info, { state_change = true, visibility = { displayed = true } }
      ))
    end
    return true
  end
end

new_lock_utils.clear_busy_state = function(device, status, override_busy_check)
  if override_busy_check then
    return
  end
  local command = device:get_field(new_lock_utils.COMMAND_NAME)
  local active_credential = device:get_field(new_lock_utils.ACTIVE_CREDENTIAL)
  if command ~= nil then
    local command_result_info = {
      commandName = command.name,
      statusCode = status
    }
    if command.type == new_lock_utils.LOCK_USERS then
      if active_credential ~= nil and active_credential.userIndex ~= nil then
        command_result_info.userIndex = active_credential.userIndex
      end
      device:emit_event(capabilities.lockUsers.commandResult(
        command_result_info, { state_change = true, visibility = { displayed = true } }
      ))
    else
      if active_credential ~= nil and active_credential.userIndex ~= nil then
        command_result_info.userIndex = active_credential.userIndex
      end
      if active_credential ~= nil and active_credential.credentialIndex ~= nil then
        command_result_info.credentialIndex = active_credential.credentialIndex
      end
      device:emit_event(capabilities.lockCredentials.commandResult(
        command_result_info, { state_change = true, visibility = { displayed = true } }
      ))
    end
  end

  device:set_field(new_lock_utils.ACTIVE_CREDENTIAL, nil)
  device:set_field(new_lock_utils.COMMAND_NAME, nil)
  device:set_field(new_lock_utils.BUSY, false)
end

new_lock_utils.reload_tables = function(device)
  local users = device:get_latest_state("main", capabilities.lockUsers.ID, capabilities.lockUsers.users.NAME, {})
  local credentials = device:get_latest_state("main", capabilities.lockCredentials.ID, capabilities.lockCredentials.credentials.NAME, {})
  if next(users) ~= nil then
    device:set_field(new_lock_utils.LOCK_USERS, users)
  end
  if next(credentials) ~= nil then
    device:set_field(new_lock_utils.LOCK_CREDENTIALS, credentials)
  end

  device:set_field(new_lock_utils.TABLES_LOADED, true)
end

new_lock_utils.get_users = function(device)
  if not device:get_field(new_lock_utils.TABLES_LOADED) then
    new_lock_utils.reload_tables(device)
  end

  local users = device:get_field(new_lock_utils.LOCK_USERS)
  return users ~= nil and users or {}
end

new_lock_utils.get_user = function(device, user_index)
  for _, user in pairs(new_lock_utils.get_users(device)) do
    if user.userIndex == user_index then
      return user
    end
  end

  return nil
end

new_lock_utils.get_available_user_index = function(device)
  local max = device:get_latest_state("main", capabilities.lockUsers.ID,
    capabilities.lockUsers.totalUsersSupported.NAME, 8)
  local current_users = new_lock_utils.get_users(device)
  local available_index = nil
  local used_index = {}
  for _, user in pairs(current_users) do
    used_index[user.userIndex] = true
  end
  if current_users ~= {} then
    for index = 1, max do
      if used_index[index] == nil then
        available_index = index
        break
      end
    end
  else
    available_index = INITIAL_INDEX
  end
  return available_index
end

new_lock_utils.get_credentials = function(device)
  if not device:get_field(new_lock_utils.TABLES_LOADED) then
    new_lock_utils.reload_tables(device)
  end

  local credentials = device:get_field(new_lock_utils.LOCK_CREDENTIALS)
  return credentials ~= nil and credentials or {}
end

new_lock_utils.get_credential = function(device, credential_index)
  for _, credential in pairs(new_lock_utils.get_credentials(device)) do
    if credential.credentialIndex == credential_index then
      return credential
    end
  end
  return nil
end

new_lock_utils.get_credential_by_user_index = function(device, user_index)
  for _, credential in pairs(new_lock_utils.get_credentials(device)) do
    if credential.userIndex == user_index then
      return credential
    end
  end

  return nil
end

new_lock_utils.get_available_credential_index = function(device)
  local max = device:get_latest_state("main", capabilities.lockCredentials.ID,
    capabilities.lockCredentials.pinUsersSupported.NAME, 8)
  local current_credentials = new_lock_utils.get_credentials(device)
  local available_index = nil
  local used_index = {}
  for _, credential in pairs(current_credentials) do
    used_index[credential.credentialIndex] = true
  end
  if current_credentials ~= {} then
    for index = 1, max do
      if used_index[index] == nil then
        available_index = index
        break
      end
    end
  else
    available_index = INITIAL_INDEX
  end
  return available_index
end

new_lock_utils.create_user = function(device, user_name, user_type, user_index)
  if user_name == nil then
    user_name = "Guest" .. user_index
  end

  local current_users = new_lock_utils.get_users(device)
  table.insert(current_users, { userIndex = user_index, userType = user_type, userName = user_name })
  device:set_field(new_lock_utils.LOCK_USERS, current_users)
end

new_lock_utils.delete_user = function(device, user_index)
  local current_users = new_lock_utils.get_users(device)
  local status_code = new_lock_utils.STATUS_FAILURE

  for index, user in pairs(current_users) do
    if user.userIndex == user_index then
      -- table.remove causes issues if we are removing while iterating.
      -- instead set the value as nil and let `prep_table` handle removing it.
      current_users[index] = nil
      device:set_field(new_lock_utils.LOCK_USERS, current_users)
      status_code = new_lock_utils.STATUS_SUCCESS
      break
    end
  end
  return status_code
end

new_lock_utils.add_credential = function(device, user_index, credential_type, credential_index)
  local credentials = new_lock_utils.get_credentials(device)
  table.insert(credentials,
    { userIndex = user_index, credentialIndex = credential_index, credentialType = credential_type })
  device:set_field(new_lock_utils.LOCK_CREDENTIALS, credentials)
  return new_lock_utils.STATUS_SUCCESS
end

new_lock_utils.delete_credential = function(device, credential_index)
  local credentials = new_lock_utils.get_credentials(device)
  local status_code = new_lock_utils.STATUS_FAILURE

  for index, credential in pairs(credentials) do
    if credential.credentialIndex == credential_index then
      new_lock_utils.delete_user(device, credential.userIndex)
      -- table.remove causes issues if we are removing while iterating.
      -- instead set the value as nil and let `prep_table` handle removing it.
      credentials[index] = nil
      device:set_field(new_lock_utils.LOCK_CREDENTIALS, credentials)
      status_code = new_lock_utils.STATUS_SUCCESS
      break
    end
  end

  return status_code
end

new_lock_utils.update_credential = function(device, credential_index, user_index, credential_type)
  local credentials = new_lock_utils.get_credentials(device)
  local status_code = new_lock_utils.STATUS_FAILURE

  for _, credential in pairs(credentials) do
    if credential.credentialIndex == credential_index then
      credential.credentialType = credential_type
      credential.userIndex = user_index
      device:set_field(new_lock_utils.LOCK_CREDENTIALS, credentials)
      status_code = new_lock_utils.STATUS_SUCCESS
      break
    end
  end
  return status_code
end

-- emit_event doesn't like having `nil` values in the table. Remove any if they are present.
new_lock_utils.prep_table = function(data)
    local clean_table = {}
    for _, value in pairs(data) do
        if value ~= nil then
            clean_table[#clean_table + 1] = value -- Append to the end of the new array
        end
    end
    return clean_table
end

new_lock_utils.send_events = function(device, type)
  if type == nil or type == new_lock_utils.LOCK_USERS then
    local current_users = new_lock_utils.prep_table(new_lock_utils.get_users(device))
    device:emit_event(capabilities.lockUsers.users(current_users,
      {state_change = true, visibility = { displayed = true } }))
  end
  if type == nil or type == new_lock_utils.LOCK_CREDENTIALS then
    local credentials = new_lock_utils.prep_table(new_lock_utils.get_credentials(device))
    device:emit_event(capabilities.lockCredentials.credentials(credentials,
      { state_change = true,  visibility = { displayed = true } }))
  end
end

new_lock_utils.get_code_id_from_notification_event = function(event_params, v1_alarm_level)
  -- some locks do not properly include the code ID in the event params, but do encode it
  -- in the v1 alarm level
  local code_id = v1_alarm_level
  if event_params ~= nil and event_params ~= "" then
    event_params = {event_params:byte(1,-1)}
    code_id = (#event_params == 1) and event_params[1] or event_params[3]
  end
  return tostring(code_id)
end

-- This is the part of the notifcation event handler code from the base driver
-- that deals with lock code programming events
new_lock_utils.base_driver_code_event_handler = function(driver, device, cmd)
  local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
  local access_control_event = Notification.event.access_control
  if (cmd.args.notification_type == Notification.notification_type.ACCESS_CONTROL) then
    local event = cmd.args.event
    local credential_index = tonumber(new_lock_utils.get_code_id_from_notification_event(cmd.args.event_parameter, cmd.args.v1_alarm_level))
    local active_credential = device:get_field(new_lock_utils.ACTIVE_CREDENTIAL)
    local status = new_lock_utils.STATUS_SUCCESS
    local command = device:get_field(new_lock_utils.COMMAND_NAME)
    local emit_event = false

    if (event == access_control_event.ALL_USER_CODES_DELETED) then
      -- all credentials have been deleted
      for _, credential in pairs(new_lock_utils.get_credentials(device)) do
        new_lock_utils.delete_credential(device, credential.credentialIndex)
        emit_event = true
      end
    elseif (event == access_control_event.SINGLE_USER_CODE_DELETED) then
      -- credential has been deleted.
      if new_lock_utils.get_credential(device, credential_index) ~= nil then
        new_lock_utils.delete_credential(device, credential_index)
        emit_event = true
      end
    elseif (event == access_control_event.NEW_USER_CODE_ADDED) then
      if command ~= nil and command.name == new_lock_utils.ADD_CREDENTIAL then
      -- create credential if not already present.
        if new_lock_utils.get_credential(device, credential_index) == nil then
          new_lock_utils.add_credential(device,
            active_credential.userIndex,
            active_credential.credentialType,
            credential_index)
          emit_event = true
        end
      elseif command ~= nil and command.name == new_lock_utils.UPDATE_CREDENTIAL then
        -- update credential
        local credential = new_lock_utils.get_credential(device, credential_index)
        if credential ~= nil then
          new_lock_utils.update_credential(device, credential.credentialIndex, credential.userIndex, credential.credentialType)
          emit_event = true
        end
      else
        -- out-of-band update. Don't add if already in table.
        if new_lock_utils.get_credential(device, credential_index) == nil then
          local new_user_index = new_lock_utils.get_available_user_index(device)
          if new_user_index ~= nil then
            new_lock_utils.create_user(device, nil, "guest", new_user_index)
            new_lock_utils.add_credential(device,
              new_user_index,
              new_lock_utils.CREDENTIAL_TYPE,
              credential_index)
            emit_event = true
          else
            status = new_lock_utils.STATUS_RESOURCE_EXHAUSTED
          end
        end
      end
    elseif (event == access_control_event.NEW_USER_CODE_NOT_ADDED_DUE_TO_DUPLICATE_CODE) then
      -- adding credential failed since code already exists.
      -- remove the created user if one got made. There is no associated credential.
      status = new_lock_utils.STATUS_DUPLICATE
      if active_credential ~= nil then new_lock_utils.delete_user(device, active_credential.userIndex) end
    elseif (event == access_control_event.NEW_PROGRAM_CODE_ENTERED_UNIQUE_CODE_FOR_LOCK_CONFIGURATION) then
      -- master code changed -- should we send an index with this?
      device:emit_event(capabilities.lockCredentials.commandResult(
        {commandName = new_lock_utils.UPDATE_CREDENTIAL, statusCode = new_lock_utils.STATUS_SUCCESS},
        { state_change = true, visibility = { displayed = true } }
      ))
    end

    -- handle emitting events if any changes occured.
    if emit_event then
      new_lock_utils.send_events(device)
    end
    -- clear the busy state and handle the commandStatus
    -- ignore handling the busy state for some commands, they are handled within their own handlers
    if command ~= nil and command ~= new_lock_utils.DELETE_ALL_CREDENTIALS and command ~= new_lock_utils.DELETE_ALL_USERS then
      new_lock_utils.clear_busy_state(device, status)
    end
  end
end

new_lock_utils.door_operation_event_handler = function(driver, device, cmd)
  local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
  local access_control_event = Notification.event.access_control
  if (cmd.args.notification_type == Notification.notification_type.ACCESS_CONTROL) then
    local event = cmd.args.event
    if (event >= access_control_event.MANUAL_LOCK_OPERATION and event <= access_control_event.LOCK_JAMMED) then
      local event_to_send

      local METHOD = {
        KEYPAD = "keypad",
        MANUAL = "manual",
        COMMAND = "command",
        AUTO = "auto"
      }

      local DELAY_LOCK_EVENT = "_delay_lock_event"
      local DELAY_LOCK_EVENT_TIMER = "_delay_lock_event_timer"
      local MAX_DELAY = 10

      if ((event >= access_control_event.MANUAL_LOCK_OPERATION and
            event <= access_control_event.KEYPAD_UNLOCK_OPERATION) or
            event == access_control_event.AUTO_LOCK_LOCKED_OPERATION) then
        -- even event codes are unlocks, odd event codes are locks
        local events = {[0] = capabilities.lock.lock.unlocked(), [1] = capabilities.lock.lock.locked()}
        event_to_send = events[event & 1]
      elseif (event >= access_control_event.MANUAL_NOT_FULLY_LOCKED_OPERATION and
              event <= access_control_event.LOCK_JAMMED) then
        event_to_send = capabilities.lock.lock.unknown()
      end

      if (event_to_send ~= nil) then
        local method_map = {
          [access_control_event.MANUAL_UNLOCK_OPERATION] = METHOD.MANUAL,
          [access_control_event.MANUAL_LOCK_OPERATION] = METHOD.MANUAL,
          [access_control_event.MANUAL_NOT_FULLY_LOCKED_OPERATION] = METHOD.MANUAL,
          [access_control_event.RF_LOCK_OPERATION] = METHOD.COMMAND,
          [access_control_event.RF_UNLOCK_OPERATION] = METHOD.COMMAND,
          [access_control_event.RF_NOT_FULLY_LOCKED_OPERATION] = METHOD.COMMAND,
          [access_control_event.KEYPAD_LOCK_OPERATION] = METHOD.KEYPAD,
          [access_control_event.KEYPAD_UNLOCK_OPERATION] = METHOD.KEYPAD,
          [access_control_event.AUTO_LOCK_LOCKED_OPERATION] = METHOD.AUTO,
          [access_control_event.AUTO_LOCK_NOT_FULLY_LOCKED_OPERATION] = METHOD.AUTO
        }

        event_to_send["data"] = {method = method_map[event]}

        -- SPECIAL CASES:
        if (event == access_control_event.MANUAL_UNLOCK_OPERATION and cmd.args.event_parameter == 2) then
          -- functionality from DTH, some locks can distinguish being manually locked via keypad
          event_to_send.data.method = METHOD.KEYPAD
        elseif (event == access_control_event.KEYPAD_LOCK_OPERATION or event == access_control_event.KEYPAD_UNLOCK_OPERATION) then
          local code_id = cmd.args.v1_alarm_level
          if cmd.args.event_parameter ~= nil and string.len(cmd.args.event_parameter) ~= 0 then
            local event_params = { cmd.args.event_parameter:byte(1, -1) }
            code_id = (#event_params == 1) and event_params[1] or event_params[3]
          end
          local user_id = nil
          local credential = new_lock_utils.get_credential(device, code_id)
          if (credential ~= nil) then
            user_id = credential.userIndex
          end
          if user_id ~= nil then event_to_send["data"] = { userIndex = user_id, method = event_to_send["data"].method } end
        end

        -- if this is an event corresponding to a recently-received attribute report, we
        -- want to set our delay timer for future lock attribute report events
        if device:get_latest_state(
          "main",
          capabilities.lock.ID,
          capabilities.lock.lock.ID) == event_to_send.value.value then
          local preceding_event_time = device:get_field(DELAY_LOCK_EVENT) or 0
          local socket = require "socket"
          local time_diff = socket.gettime() - preceding_event_time
          if time_diff < MAX_DELAY then
            device:set_field(DELAY_LOCK_EVENT, time_diff)
          end
        end

        local timer = device:get_field(DELAY_LOCK_EVENT_TIMER)
        if timer ~= nil then
          device.thread:cancel_timer(timer)
          device:set_field(DELAY_LOCK_EVENT_TIMER, nil)
        end

        device:emit_event(event_to_send)
      end
    end
  end
end

return new_lock_utils
