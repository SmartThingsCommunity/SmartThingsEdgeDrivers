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

-- Zigbee Spec Utils
local clusters                = require "st.zigbee.zcl.clusters"
local LockCluster             = clusters.DoorLock

-- Capabilities
local capabilities              = require "st.capabilities"

-- Enums
local UserStatusEnum            = LockCluster.types.DrlkUserStatus
local ProgrammingEventCodeEnum  = LockCluster.types.ProgramEventCode

local SHIFT_INDEX_CHECK = 256
local YALE_MAX_USERS_OVERRIDE = 10 -- yale supports 250 codes... we're not going to iterate through all that.

local lock_utils = (require "new_lock_utils")

local get_pin_response_handler = function(driver, device, zb_mess)
  local credential_index = tonumber(zb_mess.body.zcl_body.user_id.value)
  local active_credential = device:get_field(lock_utils.ACTIVE_CREDENTIAL)
  local command = device:get_field(lock_utils.COMMAND_NAME)
  local status = lock_utils.STATUS_SUCCESS
  local emit_event = false

  if (zb_mess.body.zcl_body.user_status.value == UserStatusEnum.OCCUPIED_ENABLED) then
    if command ~= nil and command.name == lock_utils.ADD_CREDENTIAL then
      -- create credential if not already present.
      if lock_utils.get_credential(device, credential_index) == nil then
        lock_utils.add_credential(device,
          active_credential.userIndex,
          active_credential.credentialType,
          credential_index)

        emit_event = true
      end
    elseif command ~= nil and command.name == lock_utils.UPDATE_CREDENTIAL then
      -- update credential
      local credential = lock_utils.get_credential(device, credential_index)
      if credential ~= nil then
        lock_utils.update_credential(device, credential.credentialIndex, credential.userIndex, credential.credentialType)
        emit_event = true
      end
    else
      -- Called by reloading the codes. Don't add if already in table.
      if lock_utils.get_credential(device, credential_index) == nil then
        local new_user_index = lock_utils.get_available_user_index(device)
        if new_user_index ~= nil then
          lock_utils.create_user(device, nil, "guest", new_user_index)
          lock_utils.add_credential(device,
            new_user_index,
            lock_utils.CREDENTIAL_TYPE,
            credential_index)
          emit_event = true
        else
          status = lock_utils.STATUS_RESOURCE_EXHAUSTED
        end
      end
    end
  elseif zb_mess.body.zcl_body.user_status.value == UserStatusEnum.AVAILABLE and command ~= nil and command.name == lock_utils.ADD_CREDENTIAL then
    -- tried to add a code that already is in use.
    -- remove the created user if one got made. There is no associated credential.
    status = lock_utils.STATUS_DUPLICATE
    lock_utils.delete_user(device, active_credential.userIndex)
  else
    if lock_utils.get_credential(device, credential_index) ~= nil then
      -- Credential has been deleted.
      lock_utils.delete_credential(device, credential_index)
      emit_event = true
    end
  end

  if (credential_index == device:get_field(lock_utils.CHECKING_CODE)) then
    -- the credential we're checking has arrived
    local last_slot = YALE_MAX_USERS_OVERRIDE
    if (credential_index >= last_slot) then
      device:set_field(lock_utils.CHECKING_CODE, nil)
      emit_event = true
    else
      local checkingCode = device:get_field(lock_utils.CHECKING_CODE) + 1
      device:set_field(lock_utils.CHECKING_CODE, checkingCode)
      device:send(LockCluster.server.commands.GetPINCode(device, checkingCode))
    end
  end

  if emit_event then
    device:emit_event(capabilities.lockUsers.users(lock_utils.get_users(device),
      {  state_change = true, visibility = { displayed = true } }))
    device:emit_event(capabilities.lockCredentials.credentials(lock_utils.get_credentials(device),
      { state_change = true,  visibility = { displayed = true } }))
  end

  -- ignore handling the busy state for these commands, they are handled within their own handlers
  if command ~= nil and command ~= lock_utils.DELETE_ALL_CREDENTIALS and command ~= lock_utils.DELETE_ALL_USERS then
    lock_utils.clear_busy_state(device, status)
  end
end

local programming_event_handler = function(driver, device, zb_mess)
  local credential_index = tonumber(zb_mess.body.zcl_body.user_id.value)
  local command = device:get_field(lock_utils.COMMAND_NAME)
  local emit_events = false

  if credential_index >= SHIFT_INDEX_CHECK then
    -- Index is wonky, shift it to get proper value
    credential_index = tonumber(zb_mess.body.zcl_body.user_id.value) >> 8
  end

  if (zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.MASTER_CODE_CHANGED) then
    -- Master code updated
    device:emit_event(capabilities.lockCredentials.commandResult(
      {commandName = lock_utils.UPDATE_CREDENTIAL, statusCode = lock_utils.STATUS_SUCCESS},
      { state_change = true, visibility = { displayed = false } }
    ))
  elseif (zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.PIN_CODE_DELETED) then
    if (zb_mess.body.zcl_body.user_id.value == 0xFFFF) then
      -- All credentials deleted
      local current_credentials = lock_utils.get_credentials(device)
      for _, credential in pairs(current_credentials) do
        lock_utils.delete_credential(device, credential.credentialIndex)
        emit_events = true
      end
    else
      -- One credential deleted
      if (lock_utils.get_credential(device, credential_index) ~= nil) then
        lock_utils.delete_credential(device, credential_index)
        emit_events = true
      end
    end
  elseif (zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.PIN_CODE_ADDED or
      zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.PIN_CODE_CHANGED) then
    if lock_utils.get_credential(device, credential_index) == nil and command == nil then
      local user_index = lock_utils.get_available_user_index(device)
      if user_index ~= nil then
        lock_utils.create_user(device, nil, "guest", user_index)
        lock_utils.add_credential(device,
          user_index,
          lock_utils.CREDENTIAL_TYPE,
          credential_index)
        emit_events = true
      end
    end
  end

  if emit_events then
    device:emit_event(capabilities.lockUsers.users(lock_utils.get_users(device),
      {  state_change = true, visibility = { displayed = true } }))
    device:emit_event(capabilities.lockCredentials.credentials(lock_utils.get_credentials(device),
      {  state_change = true, visibility = { displayed = true } }))
  end
end

local yale_door_lock_driver = {
  NAME = "Yale Door Lock",
  zigbee_handlers = {
    cluster = {
      [LockCluster.ID] = {
        [LockCluster.client.commands.GetPINCodeResponse.ID] = get_pin_response_handler,
        [LockCluster.client.commands.ProgrammingEventNotification.ID] = programming_event_handler,
      }
    }
  },

  sub_drivers = { require("using-new-capabilities.yale.yale-bad-battery-reporter") },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "ASSA ABLOY iRevo" or device:get_manufacturer() == "Yale"
  end
}

return yale_door_lock_driver
