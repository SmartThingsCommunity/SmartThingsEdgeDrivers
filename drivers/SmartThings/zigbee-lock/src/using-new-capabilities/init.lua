-- Copyright 2022 SmartThings
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

local lock_utils = require "lock_utils"

local socket = require "cosock.socket"
local lock_utils = require "lock_utils"

local DELAY_LOCK_EVENT = "_delay_lock_event"
local MAX_DELAY = 10

local INITIAL_CREDENTIAL_INDEX = 1 -- only used to obtain the next available index.

local add_user_handler = function(driver, device, command)
  local cmdName = "addUser"
  local userName = command.args.userName
  local userType = command.args.userType

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, INITIAL_CREDENTIAL_INDEX, {persist = true})
  device:set_field(lock_utils.USER_NAME, userName, {persist = true})
  device:set_field(lock_utils.USER_TYPE, userType, {persist = true})

  -- Send a request to server to get an index. 
  local ep = device:component_to_endpoint(command.component)
  device:send(LockCluster.server.commands.GetUser(device, ep, INITIAL_CREDENTIAL_INDEX))
end

local update_user_handler = function(driver, device, command)
-- TODO --
print("---- PK TODO --- ")
end

local delete_user_handler = function(driver, device, command)
-- TODO
end

local delete_all_users_handler = function(driver, device, command)
-- TODO
end

local add_credential_handler = function(driver, device, command)
-- TODO
end

local update_credential_handler = function(driver, device, command)
-- TODO
end

local delete_credential_handler = function(driver, device, command)
-- TODO
end

local delete_all_credentials_handler = function(driver, device, command)
-- TODO
end

local max_code_length_handler = function(driver, device, value)
  device:emit_event(LockCredentials.maxPinCodeLen(value.value, {visibility = {displayed = false}}))
end

local min_code_length_handler = function(driver, device, value)
  device:emit_event(LockCredentials.minPinCodeLen(value.value, {visibility = {displayed = false}}))
end

local max_codes_handler = function(driver, device, value)
  device:emit_event(LockCredentials.pinUsersSupported(value.value, {visibility = {displayed = false}}))
end

local get_pin_response_handler = function(driver, device, zb_mess)
  local event = LockCodes.codeChanged("", { state_change = true })
  local code_slot = tostring(zb_mess.body.zcl_body.user_id.value)
  event.data = {codeName = lock_utils.get_code_name(device, code_slot)}
  if (zb_mess.body.zcl_body.user_status.value == UserStatusEnum.OCCUPIED_ENABLED) then
    -- Code slot is occupied
    event.value = code_slot .. lock_utils.get_change_type(device, code_slot)
    local lock_codes = lock_utils.get_lock_codes(device)
    lock_codes[code_slot] = event.data.codeName
    device:emit_event(event)
    lock_utils.lock_codes_event(device, lock_codes)
    lock_utils.reset_code_state(device, code_slot)
  else
    -- Code slot is unoccupied
    if (lock_utils.get_lock_codes(device)[code_slot] ~= nil) then
      -- Code has been deleted
      lock_utils.lock_codes_event(device, lock_utils.code_deleted(device, code_slot))
    else
      -- Code is unset
      event.value = code_slot .. " unset"
      device:emit_event(event)
    end
  end

  code_slot = tonumber(code_slot)
  if (code_slot == device:get_field(lock_utils.CHECKING_CODE)) then
    -- the code we're checking has arrived
    local last_slot = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME) - 1
    if (code_slot >= last_slot) then
      device:emit_event(LockCodes.scanCodes("Complete", { visibility = { displayed = false } }))
      device:set_field(lock_utils.CHECKING_CODE, nil)
    else
      local checkingCode = device:get_field(lock_utils.CHECKING_CODE) + 1
      device:set_field(lock_utils.CHECKING_CODE, checkingCode)
      device:send(LockCluster.server.commands.GetPINCode(device, checkingCode))
    end
  end
end

local programming_event_handler = function(driver, device, zb_mess)
  local event = LockCodes.codeChanged("", { state_change = true })
  local code_slot = tostring(zb_mess.body.zcl_body.user_id.value)
  event.data = {}
  if (zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.MASTER_CODE_CHANGED) then
    -- Master code changed
    event.value = "0 set"
    event.data = {codeName = "Master Code"}
    device:emit_event(event)
  elseif (zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.PIN_CODE_DELETED) then
    if (zb_mess.body.zcl_body.user_id.value == 0xFF) then
      -- All codes deleted
      for cs, _ in pairs(lock_utils.get_lock_codes(device)) do
        lock_utils.code_deleted(device, cs)
      end
      lock_utils.lock_codes_event(device, {})
    else
      -- One code deleted
      if (lock_utils.get_lock_codes(device)[code_slot] ~= nil) then
        lock_utils.lock_codes_event(device, lock_utils.code_deleted(device, code_slot))
      end
    end
  elseif (zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.PIN_CODE_ADDED or
          zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.PIN_CODE_CHANGED) then
    -- Code added or changed
    local change_type = lock_utils.get_change_type(device, code_slot)
    local code_name = lock_utils.get_code_name(device, code_slot)
    event.value = code_slot .. change_type
    event.data = {codeName = code_name}
    device:emit_event(event)
    if (change_type == " set") then
      local lock_codes = lock_utils.get_lock_codes(device)
      lock_codes[code_slot] = code_name
      lock_utils.lock_codes_event(device, lock_codes)
    end
  end
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
    if (source == 0 and device:supports_capability_by_id(capabilities.lockCodes.ID)) then --keypad
      local code_id = zb_rx.body.zcl_body.user_id.value
      local code_name = "Code "..code_id
      local lock_codes = device:get_field("lockCodes")
      if (lock_codes ~= nil and
          lock_codes[code_id] ~= nil) then
        code_name = lock_codes[code_id]
      end
      event.data = {method = METHOD[0], codeId = code_id .. "", codeName = code_name}
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
    },
    sub_drivers = {
        require("using-new-capabilities.samsungsds"),
        require("using-new-capabilities.yale-fingerprint-lock"),
        require("using-new-capabilities.yale"),
        require("using-new-capabilities.lock-without-codes")
    },
    can_handle = function(opts, driver, device, ...)
        local lock_codes_migrated = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.migrated.NAME, false)
        if lock_codes_migrated then
            print("--- PK NEW CAPABILITIES --")
            local subdriver = require("using-new-capabilities")
            return true, subdriver
        end
        return false
    end
}

return new_capabilities_driver