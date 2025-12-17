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
local LockCredentials = capabilities.lockCredentials
local LockUsers = capabilities.lockUsers
local INITIAL_INDEX = 1

local new_lock_utils = {
  -- Constants
  ADD_CREDENTIAL = "addCredential",
  ADD_USER = "addUser",
  COMMAND_NAME = "commandName",
  CREDENTIAL_TYPE = "pin",
  CHECKING_CODE = "checkingCode",
  DELETE_ALL_CREDENTIALS = "deleteAllCredentials",
  DELETE_ALL_USERS = "deleteAllUsers",
  DELETE_CREDENTIAL = "deleteCredential",
  DELETE_USER = "deleteUser",
  LOCK_CREDENTIALS = "lockCredentials",
  LOCK_USERS = "lockUsers",
  PENDING_CREDENTIAL = "pendingCredential",
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

new_lock_utils.get_users = function(device)
  local users = device:get_field(new_lock_utils.LOCK_USERS)
  return users ~= nil and users or {}
end

new_lock_utils.get_user = function(device, user_index)
  for _, user in ipairs(new_lock_utils.get_users(device)) do
    if user.userIndex == user_index then
      return user
    end
  end

  return nil
end

new_lock_utils.get_available_user_index = function(device)
  local max_users = device:get_latest_state("main", capabilities.lockUsers.ID,
    capabilities.lockUsers.totalUsersSupported.NAME, 0)
  local current_users = new_lock_utils.get_users(device)
  if current_users == nil and max_users ~= 0 then
    return INITIAL_INDEX
  elseif current_users ~= nil then
    for index = 1, max_users do
      if current_users["user" .. index] == nil then
        return index
      end
    end
  end

  return nil
end

new_lock_utils.get_credentials = function(device)
  local credentials = device:get_field(new_lock_utils.LOCK_CREDENTIALS)
  return credentials ~= nil and credentials or {}
end

new_lock_utils.get_credential = function(device, credential_index)
  for _, credential in ipairs(new_lock_utils.get_credentials(device)) do
    if credential.credentialIndex == credential_index then
      return credential
    end
  end
  return nil
end

new_lock_utils.get_credential_by_user_index = function(device, user_index)
  for _, credential in ipairs(new_lock_utils.get_credentials(device)) do
    if credential.userIndex == user_index then
      return credential
    end
  end

  return nil
end

new_lock_utils.get_available_credential_index = function(device)
  local max = device:get_latest_state("main", capabilities.lockCredentials.ID,
    capabilities.lockCredentials.pinUsersSupported.NAME, 0)
  local current_credentials = new_lock_utils.get_credentials(device)
  local available_index = nil
  local used_index = {}

  for i, _ in ipairs(current_credentials) do
    used_index[i] = true
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
  local status_code = new_lock_utils.STATUS_SUCCESS
  local available_index = new_lock_utils.get_available_user_index(device)
  if available_index == nil then
    -- Can't add any users - update commandResult statusCode
    status_code = new_lock_utils.STATUS_RESOURCE_EXHAUSTED
  else
    local current_users = new_lock_utils.get_users(device)
    -- use the passed in index if it's set
    if user_index ~= nil then
      available_index = user_index
    end
    if user_name == nil then
      user_name = "USER_" .. available_index
    end
    current_users["user"..available_index] = { userIndex = available_index, userType = user_type, userName = user_name }
    device:set_field(new_lock_utils.LOCK_USERS, current_users, { persist = true })
  end

  return status_code
end

new_lock_utils.delete_user = function(device, user_index)
  local current_users = new_lock_utils.get_users(device)
  local status_code = new_lock_utils.STATUS_FAILURE

  for index, user in pairs(current_users) do
    if user.userIndex == user_index then
      current_users[index] = nil
      device:set_field(new_lock_utils.LOCK_USERS, current_users)
      status_code = new_lock_utils.STATUS_SUCCESS
      break
    end
  end

  return status_code
end

new_lock_utils.add_credential = function(device, user_index, user_type, credential_type, credential_index)
  -- need to also create a user if one does not exist at the user index.
  local status = new_lock_utils.STATUS_SUCCESS
  if user_index == 0 then
    user_index = new_lock_utils.get_available_user_index(device)
    status = new_lock_utils.create_user(device, nil, user_type, user_index)
  elseif new_lock_utils.get_user(device, tonumber(user_index)) == nil then
    status = new_lock_utils.create_user(device, nil, user_type, user_index)
  end

  if status ~= new_lock_utils.STATUS_SUCCESS then
    return status
  end

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
      table.remove(credentials, index)
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

  for _, credential in ipairs(credentials) do
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

return new_lock_utils
