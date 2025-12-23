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

-- Zigbee Driver utilities
local defaults          = require "st.zigbee.defaults"
local device_management = require "st.zigbee.device_management"
local ZigbeeDriver      = require "st.zigbee"
local log               = require "log"
local utils             = require "st.utils"


-- Zigbee Spec Utils
local clusters                = require "st.zigbee.zcl.clusters"
local Alarm                   = clusters.Alarms
local LockCluster             = clusters.DoorLock
local PowerConfiguration      = clusters.PowerConfiguration

-- Capabilities
local capabilities              = require "st.capabilities"
local Battery                   = capabilities.battery
local Lock                      = capabilities.lock
local LockCredentials           = capabilities.lockCredentials
local LockUsers                 = capabilities.lockUsers

-- Enums
local UserStatusEnum            = LockCluster.types.DrlkUserStatus
local UserTypeEnum              = LockCluster.types.DrlkUserType
local ProgrammingEventCodeEnum  = LockCluster.types.ProgramEventCode

local socket = require "cosock.socket"
local lock_utils = require "new_lock_utils"

local DELAY_LOCK_EVENT = "_delay_lock_event"
local MAX_DELAY = 10

local reload_all_codes = function(device)
  -- starts at first user code index then iterates through all lock codes as they come in
  device:send(LockCluster.attributes.SendPINOverTheAir:write(device, true))
  if (device:get_latest_state("main", capabilities.lockCredentials.ID, capabilities.lockCredentials.maxPinCodeLen.NAME) == nil) then
    device:send(LockCluster.attributes.MaxPINCodeLength:read(device))
  end
  if (device:get_latest_state("main", capabilities.lockCredentials.ID, capabilities.lockCredentials.minPinCodeLen.NAME) == nil) then
    device:send(LockCluster.attributes.MinPINCodeLength:read(device))
  end
  if (device:get_latest_state("main", capabilities.lockCredentials.ID, capabilities.lockCredentials.pinUsersSupported.NAME) == nil) then
    device:send(LockCluster.attributes.NumberOfPINUsersSupported:read(device))
  end
  if (device:get_latest_state("main", capabilities.lockUsers.ID, capabilities.lockUsers.totalUsersSupported.NAME) == nil) then
    device:send(LockCluster.attributes.NumberOfTotalUsersSupported:read(device))
  end
  if (device:get_field(lock_utils.CHECKING_CODE) == nil) then
    device:set_field(lock_utils.CHECKING_CODE, 1)
  end

  device:send(LockCluster.server.commands.GetPINCode(device, device:get_field(lock_utils.CHECKING_CODE)))
end

local refresh = function(driver, device, cmd)
  device:refresh()
  device:send(LockCluster.attributes.LockState:read(device))
  device:send(Alarm.attributes.AlarmCount:read(device))
end

local device_added = function(driver, device)
  lock_utils.reload_tables(device)

  driver:inject_capability_command(device, {
    capability = capabilities.refresh.ID,
    command = capabilities.refresh.commands.refresh.NAME,
    args = {}
  })
end

local init = function(driver, device)
  lock_utils.reload_tables(device)
  device.thread:call_with_delay(2, function(d)
    reload_all_codes(device)
  end)
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 600, 21600, 1))

  device:send(device_management.build_bind_request(device, LockCluster.ID, self.environment_info.hub_zigbee_eui))
  device:send(LockCluster.attributes.LockState:configure_reporting(device, 0, 3600, 0))

  device:send(device_management.build_bind_request(device, Alarm.ID, self.environment_info.hub_zigbee_eui))
  device:send(Alarm.attributes.AlarmCount:configure_reporting(device, 0, 21600, 0))

  device.thread:call_with_delay(2, function(d)
    reload_all_codes(device)
  end)
end

local add_user_handler = function(driver, device, command)
  if lock_utils.busy_check_and_set(device, {name = lock_utils.ADD_USER, type = lock_utils.LOCK_USERS}) then
    return
  end
  local available_index = lock_utils.get_available_user_index(device)
  local status = lock_utils.STATUS_SUCCESS
  if available_index == nil then
    status = lock_utils.STATUS_RESOURCE_EXHAUSTED
  else
    device:set_field(lock_utils.ACTIVE_CREDENTIAL, { userIndex = available_index})
    lock_utils.create_user(device, command.args.userName, command.args.userType, available_index)
  end

  if status == lock_utils.STATUS_SUCCESS then
    lock_utils.send_events(device, lock_utils.LOCK_USERS)
  end

  lock_utils.clear_busy_state(device, status)
end

local update_user_handler = function(driver, device, command)
  if lock_utils.busy_check_and_set(device, {name = lock_utils.UPDATE_USER, type = lock_utils.LOCK_USERS}) then
    return
  end

  local user_name = command.args.userName
  local user_type = command.args.userType
  local user_index = tonumber(command.args.userIndex)
  local current_users = lock_utils.get_users(device)
  local status = lock_utils.STATUS_FAILURE

  for _, user in pairs(current_users) do
    if user.userIndex == user_index then
      device:set_field(lock_utils.ACTIVE_CREDENTIAL, { userIndex = user_index})
      user.userName = user_name
      user.userType = user_type
      device:set_field(lock_utils.LOCK_USERS, current_users)
      lock_utils.send_events(device, lock_utils.LOCK_USERS)
      status = lock_utils.STATUS_SUCCESS
      break
    end
  end

  lock_utils.clear_busy_state(device, status)
end

local delete_user_handler = function(driver, device, command)
  if lock_utils.busy_check_and_set(device, {name = lock_utils.DELETE_USER, type = lock_utils.LOCK_USERS}, command.override_busy_check) then
    return
  end
  local status = lock_utils.STATUS_SUCCESS
  local user_index = tonumber(command.args.userIndex)  
  if lock_utils.get_user(device, user_index) ~= nil then

    if command.override_busy_check == nil then
      device:set_field(lock_utils.ACTIVE_CREDENTIAL, { userIndex = user_index })
    end

    local associated_credential = lock_utils.get_credential_by_user_index(device, user_index)
    if associated_credential ~= nil then
      -- if there is an associated credential with this user then delete the credential
      -- this command also handles the user deletion
      driver:inject_capability_command(device, {
        capability = capabilities.lockCredentials.ID,
        command = capabilities.lockCredentials.commands.deleteCredential.NAME,
        args = { associated_credential.credentialIndex, "pin" },
        override_busy_check = true
      })
    else
      lock_utils.delete_user(device, user_index)
      lock_utils.send_events(device, lock_utils.LOCK_USERS)
      lock_utils.clear_busy_state(device, status, command.override_busy_check)
    end
  else
    status = lock_utils.STATUS_FAILURE
    lock_utils.clear_busy_state(device, status, command.override_busy_check)
  end
end

local delete_all_users_handler = function(driver, device, command)
  if lock_utils.busy_check_and_set(device, {name = lock_utils.DELETE_ALL_USERS, type = lock_utils.LOCK_USERS}) then
    return
  end
  local status = lock_utils.STATUS_SUCCESS
  local current_users = lock_utils.get_users(device)

  local delay = 0
  for _, user in pairs(current_users) do
    device.thread:call_with_delay(delay, function()
      driver:inject_capability_command(device, {
        capability = capabilities.lockUsers.ID,
        command = capabilities.lockUsers.commands.deleteUser.NAME,
        args = {user.userIndex},
        override_busy_check = true
      })
    end)
    delay = delay + 2
  end

  device.thread:call_with_delay(delay + 4, function()
    lock_utils.clear_busy_state(device, status)
  end)
end

local add_credential_handler = function(driver, device, command)
  if lock_utils.busy_check_and_set(device, {name = lock_utils.ADD_CREDENTIAL, type = lock_utils.LOCK_CREDENTIALS}) then
    return
  end
  local user_index = tonumber(command.args.userIndex)
  local user_type = command.args.userType
  local credential_type = command.args.credentialType
  local credential_data = command.args.credentialData
  local status = lock_utils.STATUS_SUCCESS

  local credential_index = lock_utils.get_available_credential_index(device)
  if credential_index == nil then
    status = lock_utils.STATUS_RESOURCE_EXHAUSTED
  elseif user_index ~= 0 and lock_utils.get_credential_by_user_index(device, user_index) then
    status = lock_utils.STATUS_OCCUPIED
  elseif user_index ~= 0 and lock_utils.get_user(device, user_index) == nil then
    status = lock_utils.STATUS_FAILURE
  end

  if user_index == 0 then
    user_index = lock_utils.get_available_user_index(device)
    if user_index ~= nil then
      lock_utils.create_user(device, nil, user_type, user_index)
    else
      status = lock_utils.STATUS_RESOURCE_EXHAUSTED
    end
  end

  if status == lock_utils.STATUS_SUCCESS then
    -- set the pin code and then validate it was successful when the GetPINCode response is received.
    -- the credential creation and events will also be handled in that response.
    device:set_field(lock_utils.ACTIVE_CREDENTIAL,
      { userIndex = user_index, userType = user_type, credentialType = credential_type, credentialIndex = credential_index })
    device:send(LockCluster.server.commands.SetPINCode(device,
      credential_index,
      UserStatusEnum.OCCUPIED_ENABLED,
      UserTypeEnum.UNRESTRICTED,
      credential_data)
    )
    device.thread:call_with_delay(4, function(d)
      device:send(LockCluster.server.commands.GetPINCode(device, credential_index))
    end)
  else
    lock_utils.clear_busy_state(device, status)
  end
end

local update_credential_handler = function(driver, device, command)
  if lock_utils.busy_check_and_set(device, {name = lock_utils.UPDATE_CREDENTIAL, type = lock_utils.LOCK_CREDENTIALS}) then
    return
  end
  local credential_index = tonumber(command.args.credentialIndex)
  local credential_data = command.args.credentialData
  local status = lock_utils.STATUS_SUCCESS
  local credential = lock_utils.get_credential(device, credential_index)

  if credential ~= nil then
    device:set_field(lock_utils.ACTIVE_CREDENTIAL,
      { userIndex = credential.userIndex, credentialType = credential.credentialType, credentialIndex = credential.credentialIndex })
    device:send(LockCluster.server.commands.SetPINCode(device,
      credential_index,
      UserStatusEnum.OCCUPIED_ENABLED,
      UserTypeEnum.UNRESTRICTED,
      credential_data)
    )
    device.thread:call_with_delay(4, function()
      device:send(LockCluster.server.commands.GetPINCode(device, credential_index))
    end)
  else
    status = lock_utils.STATUS_FAILURE
    lock_utils.clear_busy_state(device, status)
  end
end

local delete_credential_handler = function(driver, device, command)
  if lock_utils.busy_check_and_set(device, {name = lock_utils.DELETE_CREDENTIAL, type = lock_utils.LOCK_CREDENTIALS}, command.override_busy_check) then
    return
  end

  local credential_index = tonumber(command.args.credentialIndex)
  local status = lock_utils.STATUS_SUCCESS
  local credential = lock_utils.get_credential(device, credential_index)
  if credential ~= nil then
    if command.override_busy_check == nil then
      device:set_field(lock_utils.ACTIVE_CREDENTIAL,
        { userIndex = credential.userIndex, credentialType = credential.credentialType, credentialIndex = credential.credentialIndex })
    end

    device:send(LockCluster.attributes.SendPINOverTheAir:write(device, true))
    device:send(LockCluster.server.commands.ClearPINCode(device, credential_index))
    device.thread:call_with_delay(2, function(d)
      device:send(LockCluster.server.commands.GetPINCode(device, credential_index))
    end)
  else
    status = lock_utils.STATUS_FAILURE
    lock_utils.clear_busy_state(device, status, command.override_busy_check)
  end
end

local delete_all_credentials_handler = function(driver, device, command)
  if lock_utils.busy_check_and_set(device, {name = lock_utils.DELETE_ALL_CREDENTIALS, type = lock_utils.LOCK_CREDENTIALS}) then
    return
  end
  local credentials = lock_utils.get_credentials(device)
  local status = lock_utils.STATUS_SUCCESS
  local delay = 0
  for _, credential in pairs(credentials) do
    local credential_index = tonumber(credential.credentialIndex)
    device.thread:call_with_delay(delay, function()
      device:send(LockCluster.server.commands.ClearPINCode(device, credential_index))
    end)
    device.thread:call_with_delay(delay + 2, function(d)
      device:send(LockCluster.server.commands.GetPINCode(device, credential_index))
    end)
    delay = delay + 2
  end

  device.thread:call_with_delay(delay + 4, function()
    lock_utils.clear_busy_state(device, status)
  end)
end

local max_code_length_handler = function(driver, device, value)
  device:emit_event(capabilities.lockCredentials.maxPinCodeLen(value.value, { visibility = { displayed = false } }))
end

local min_code_length_handler = function(driver, device, value)
  device:emit_event(capabilities.lockCredentials.minPinCodeLen(value.value, { visibility = { displayed = false } }))
end

local max_codes_handler = function(driver, device, value)
  device:emit_event(capabilities.lockUsers.totalUsersSupported(value.value, {visibility = {displayed = false}}))
  device:emit_event(capabilities.lockCredentials.pinUsersSupported(value.value, {visibility = {displayed = false}}))
end

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
    local last_slot = device:get_latest_state("main", capabilities.lockCredentials.ID,
      capabilities.lockCredentials.pinUsersSupported.NAME)
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
    lock_utils.send_events(device)
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

  if (zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.MASTER_CODE_CHANGED) then
    -- Master code updated
    device:emit_event(capabilities.lockCredentials.commandResult(
      {commandName = lock_utils.UPDATE_CREDENTIAL, statusCode = lock_utils.STATUS_SUCCESS},
      { state_change = true, visibility = { displayed = true } }
    ))
  elseif (zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.PIN_CODE_DELETED) then
    if (zb_mess.body.zcl_body.user_id.value == 0xFF) then
      -- All credentials deleted
      for _, credential in pairs(lock_utils.get_credentials(device)) do
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
    lock_utils.send_events(device)
  end
end

-- REMOVE THIS AFTER DONE WITH TESTING
local migrate = function(driver, device, value)
  log.error_with({ hub_logs = true }, "\n--- PK -- CURRENT USERS ---- \n" .. 
  "\n" ..utils.stringify_table(lock_utils.get_users(device)).."\n" ..
  "\n--- PK -- CURRENT CREDENTIALS ---- \n" ..
  "\n" ..utils.stringify_table(lock_utils.get_credentials(device)).."\n" ..
  "\n --------------------------------- \n")
end

local lock_operation_event_handler = function(driver, device, zb_rx)
  local event_code = zb_rx.body.zcl_body.operation_event_code.value
  local source = zb_rx.body.zcl_body.operation_event_source.value
  local OperationEventCode = require "st.zigbee.generated.zcl_clusters.DoorLock.types.OperationEventCode"
  local METHOD = {
    [0] = "keypad",
    [1] = "command",
    [2] = "manual",
    [3] = "rfid",
    [4] = "fingerprint",
    [5] = "bluetooth"
  }
  local STATUS = {
    [OperationEventCode.LOCK]            = capabilities.lock.lock.locked(),
    [OperationEventCode.UNLOCK]          = capabilities.lock.lock.unlocked(),
    [OperationEventCode.ONE_TOUCH_LOCK]  = capabilities.lock.lock.locked(),
    [OperationEventCode.KEY_LOCK]        = capabilities.lock.lock.locked(),
    [OperationEventCode.KEY_UNLOCK]      = capabilities.lock.lock.unlocked(),
    [OperationEventCode.AUTO_LOCK]       = capabilities.lock.lock.locked(),
    [OperationEventCode.MANUAL_LOCK]     = capabilities.lock.lock.locked(),
    [OperationEventCode.MANUAL_UNLOCK]   = capabilities.lock.lock.unlocked(),
    [OperationEventCode.SCHEDULE_LOCK]   = capabilities.lock.lock.locked(),
    [OperationEventCode.SCHEDULE_UNLOCK] = capabilities.lock.lock.unlocked()
  }
  local event = STATUS[event_code]
  if (event ~= nil) then
    event["data"] = {}
    if (source ~= 0 and event_code == OperationEventCode.AUTO_LOCK or
          event_code == OperationEventCode.SCHEDULE_LOCK or
          event_code == OperationEventCode.SCHEDULE_UNLOCK
        ) then
      event.data.method = "auto"
    else
      event.data.method = METHOD[source]
    end
    if (source == 0 and device:supports_capability_by_id(capabilities.lockUsers.ID)) then --keypad
      local code_id = zb_rx.body.zcl_body.user_id.value
      local code_name = "Code " .. code_id
      local user = lock_utils.get_user(device, code_id)
      if user ~= nil then
        code_name = user.userName
      end

      event.data = { method = METHOD[0], codeId = code_id .. "", codeName = code_name }
    end

    -- if this is an event corresponding to a recently-received attribute report, we
    -- want to set our delay timer for future lock attribute report events
    if device:get_latest_state(
          device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value),
          capabilities.lock.ID,
          capabilities.lock.lock.ID) == event.value.value then
      local preceding_event_time = device:get_field(DELAY_LOCK_EVENT) or 0
      local time_diff = socket.gettime() - preceding_event_time
      if time_diff < MAX_DELAY then
        device:set_field(DELAY_LOCK_EVENT, time_diff)
      end
    end

    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, event)
  end
end


local new_capabilities_driver = {
  NAME = "Lock Driver Using New Capabilities",
  supported_capabilities = {
    Lock,
    LockCredentials,
    LockUsers,
    Battery,
  },
  zigbee_handlers = {
    cluster = {
      [LockCluster.ID] = {
        [LockCluster.client.commands.GetPINCodeResponse.ID] = get_pin_response_handler,
        [LockCluster.client.commands.ProgrammingEventNotification.ID] = programming_event_handler,
        [LockCluster.client.commands.OperatingEventNotification.ID] = lock_operation_event_handler,
      }
    },
    attr = {
      [LockCluster.ID] = {
        [LockCluster.attributes.MaxPINCodeLength.ID] = max_code_length_handler,
        [LockCluster.attributes.MinPINCodeLength.ID] = min_code_length_handler,
        [LockCluster.attributes.NumberOfPINUsersSupported.ID] = max_codes_handler,
      }
    }
  },
  capability_handlers = {
    [LockUsers.ID] = {
      [LockUsers.commands.addUser.NAME] = add_user_handler,
      [LockUsers.commands.updateUser.NAME] = update_user_handler,
      [LockUsers.commands.deleteUser.NAME] = delete_user_handler,
      [LockUsers.commands.deleteAllUsers.NAME] = delete_all_users_handler,
    },
    [LockCredentials.ID] = {
      [LockCredentials.commands.addCredential.NAME] = add_credential_handler,
      [LockCredentials.commands.updateCredential.NAME] = update_credential_handler,
      [LockCredentials.commands.deleteCredential.NAME] = delete_credential_handler,
      [LockCredentials.commands.deleteAllCredentials.NAME] = delete_all_credentials_handler,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh
    },

    [capabilities.lockCodes.ID] = { -- REMOVE THIS WHEN DONE WITH TESTING
      [capabilities.lockCodes.commands.migrate.NAME] = migrate,
    },
  },
  sub_drivers = {
    require("using-new-capabilities.samsungsds"),
    require("using-new-capabilities.yale-fingerprint-lock"),
    require("using-new-capabilities.yale"),
    require("using-new-capabilities.lock-without-codes")
  },
  health_check = false,
  lifecycle_handlers = {
    added = device_added,
    init = init,
    doConfigure = do_configure
  },
  can_handle = function(opts, driver, device, ...)
    local lock_codes_migrated = device:get_latest_state("main", capabilities.lockCodes.ID,
      capabilities.lockCodes.migrated.NAME, false)
    if lock_codes_migrated then
      local subdriver = require("using-new-capabilities")
      return true, subdriver
    end
    return false
  end
}

return new_capabilities_driver
