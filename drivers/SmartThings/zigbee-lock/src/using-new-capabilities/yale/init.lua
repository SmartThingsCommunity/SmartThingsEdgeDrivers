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

-- Zigbee Spec Utils
local clusters                = require "st.zigbee.zcl.clusters"
local LockCluster             = clusters.DoorLock

-- Capabilities
local capabilities              = require "st.capabilities"
local LockCredentials           = capabilities.lockCredentials
local log                       = require "log"

-- Enums
local UserStatusEnum            = LockCluster.types.DrlkUserStatus
local UserTypeEnum              = LockCluster.types.DrlkUserType
local ProgrammingEventCodeEnum  = LockCluster.types.ProgramEventCode

local SHIFT_INDEX_CHECK = 256

local lock_utils = (require "new_lock_utils")

local programming_event_handler = function(driver, device, zb_mess)
  local credential_index = tonumber(zb_mess.body.zcl_body.user_id.value)

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
      for _, credential in pairs(lock_utils.get_credentials(device)) do
        lock_utils.delete_credential(device, credential.credentialIndex)
      end
      device:emit_event(capabilities.lockCredentials.credentials(lock_utils.get_credentials(device),
        { visibility = { displayed = false } }))
    else
      -- One credential deleted
      if (lock_utils.get_credential(device, credential_index) ~= nil) then
        lock_utils.delete_credential(device, credential_index)
        device:emit_event(capabilities.lockCredentials.credentials(lock_utils.get_credentials(device),
          { visibility = { displayed = false } }))
      end
    end
  elseif (zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.PIN_CODE_ADDED or
      zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.PIN_CODE_CHANGED) then
    if lock_utils.get_credential(device, credential_index) == nil then
      local user_index = lock_utils.get_available_user_index(device)
      lock_utils.add_credential(device, user_index,
        "guest",
        lock_utils.CREDENTIAL_TYPE,
        credential_index)
      device:emit_event(capabilities.lockCredentials.credentials(lock_utils.get_credentials(device),
        { visibility = { displayed = false } }))
    end
  end
end

local yale_door_lock_driver = {
  NAME = "Yale Door Lock",
  zigbee_handlers = {
    cluster = {
      [LockCluster.ID] = {
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
