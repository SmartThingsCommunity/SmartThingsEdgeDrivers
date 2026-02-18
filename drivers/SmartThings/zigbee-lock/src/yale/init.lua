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
local LockCodes                 = capabilities.lockCodes

-- Enums
local UserStatusEnum            = LockCluster.types.DrlkUserStatus
local UserTypeEnum              = LockCluster.types.DrlkUserType

local lock_utils = (require "lock_utils")

local reload_all_codes = function(driver, device, command)
  -- starts at first user code index then iterates through all lock codes as they come in
  device:send(LockCluster.attributes.SendPINOverTheAir:write(device, true))
  if (device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodeLength.NAME) == nil) then
    device:send(LockCluster.attributes.MaxPINCodeLength:read(device))
  end
  if (device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.minCodeLength.NAME) == nil) then
    device:send(LockCluster.attributes.MinPINCodeLength:read(device))
  end
  if (device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME) == nil) then
    device:send(LockCluster.attributes.NumberOfPINUsersSupported:read(device))
  end
  if (device:get_field(lock_utils.CHECKING_CODE) == nil) then device:set_field(lock_utils.CHECKING_CODE, 1) end
  device:emit_event(LockCodes.scanCodes("Scanning", { visibility = { displayed = false } }))
  device:send(LockCluster.server.commands.GetPINCode(device, device:get_field(lock_utils.CHECKING_CODE)))
end

local set_code = function(driver, device, command)
  if (command.args.codePIN == "") then
    driver:inject_capability_command(device, {
      capability = capabilities.lockCodes.ID,
      command = capabilities.lockCodes.commands.nameSlot.NAME,
      args = {command.args.codeSlot, command.args.codeName}
    })
  else
    local user_type = command.args.codeSlot == 0 and UserTypeEnum.MASTER_USER or UserTypeEnum.UNRESTRICTED
    device:send(LockCluster.server.commands.SetPINCode(device,
            command.args.codeSlot,
            UserStatusEnum.OCCUPIED_ENABLED,
            user_type,
            command.args.codePIN)
    )
    if (command.args.codeName ~= nil) then
      -- wait for confirmation from the lock to commit this to memory
      -- Groovy driver has a lot more info passed here as a description string, may need to be investigated
      local codeState = device:get_field(lock_utils.CODE_STATE) or {}
      codeState["setCode"..command.args.codeSlot] = command.args.codePIN
      codeState["setName"..command.args.codeSlot] = command.args.codeName
      device:set_field(lock_utils.CODE_STATE, codeState, { persist = true })
    end
    device.thread:call_with_delay(4, function(d)
      device:send(LockCluster.server.commands.GetPINCode(device, command.args.codeSlot))
    end)
  end
end

local get_pin_response_handler = function(driver, device, zb_mess)
  local event = LockCodes.codeChanged("", { state_change = true })
  local code_slot = tostring(zb_mess.body.zcl_body.user_id.value)
  local localCode = device:get_field(lock_utils.CODE_STATE)
  if localCode ~= nil then localCode = localCode["setCode"..code_slot] end
  local code_name = lock_utils.get_code_name(device, code_slot)
  local lock_codes = lock_utils.get_lock_codes(device)
  event.data = {codeName = code_name}
  if (zb_mess.body.zcl_body.user_status.value == UserStatusEnum.OCCUPIED_ENABLED) then
    -- Code slot is occupied
    if (localCode ~= nil) then
      local serverCode = zb_mess.body.zcl_body.code.value
      if (localCode == serverCode) then
        event.value = code_slot .. lock_utils.get_change_type(device, code_slot)
        device:emit_event(event)
        lock_codes[code_slot] = code_name
        lock_utils.lock_codes_event(device, lock_codes)
      else
        event.value = code_slot .. " failed"
        event.data = nil
        device:emit_event(event)
      end
      lock_utils.reset_code_state(device, code_slot)
    else
      event.value = code_slot .. lock_utils.get_change_type(device, code_slot)
      device:emit_event(event)
      lock_codes[code_slot] = code_name
      lock_utils.lock_codes_event(device, lock_codes)
    end
  else
    -- Code slot is unoccupied
    if (localCode ~= nil) then
      -- Code slot found empty during creation of a user code
      event.value = code_slot .. " failed"
      event.data = nil
      device:emit_event(event)
      event.value = code_slot .. " is not set"
      device:emit_event(event)
      lock_utils.reset_code_state(device, code_slot)
    elseif (lock_codes[code_slot] ~= nil) then
      -- Code has been deleted
      lock_utils.lock_codes_event(device, (lock_utils.code_deleted(device, code_slot)))
    else
      -- Code is unset
      event.value = code_slot .. " unset"
      device:emit_event(event)
    end
  end

  code_slot = tonumber(code_slot)
  if (code_slot == device:get_field(lock_utils.CHECKING_CODE)) then
    -- the code we're checking has arrived
    local defaultMaxCodes = 8
    if (code_slot >= defaultMaxCodes) then
      device:emit_event(LockCodes.scanCodes("Complete", { visibility = { displayed = false } }))
      device:set_field(lock_utils.CHECKING_CODE, nil)
    else
      local checkingCode = device:get_field(lock_utils.CHECKING_CODE) + 1
      device:set_field(lock_utils.CHECKING_CODE, checkingCode)
      device:send(LockCluster.server.commands.GetPINCode(device, checkingCode))
    end
  end
end

local yale_door_lock_driver = {
  NAME = "Yale Door Lock",
  zigbee_handlers = {
    cluster = {
      [LockCluster.ID] = {
        [LockCluster.client.commands.GetPINCodeResponse.ID] = get_pin_response_handler,
      }
    }
  },
  capability_handlers = {
    [LockCodes.ID] = {
      [LockCodes.commands.reloadAllCodes.NAME] = reload_all_codes,
      [LockCodes.commands.setCode.NAME] = set_code
    }
  },

  sub_drivers = { require("yale.yale-bad-battery-reporter") },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "ASSA ABLOY iRevo" or device:get_manufacturer() == "Yale"
  end
}

return yale_door_lock_driver
