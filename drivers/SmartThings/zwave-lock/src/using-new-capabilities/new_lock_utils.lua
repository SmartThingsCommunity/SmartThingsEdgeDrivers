-- Copyright 2025 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
local utils = require "st.utils"
local capabilities = require "st.capabilities"
local json = require "st.json"
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
  device:set_field(new_lock_utils.LOCK_USERS, users)
  device:set_field(new_lock_utils.LOCK_CREDENTIALS, credentials)
end

new_lock_utils.get_users = function(device)
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

return new_lock_utils
