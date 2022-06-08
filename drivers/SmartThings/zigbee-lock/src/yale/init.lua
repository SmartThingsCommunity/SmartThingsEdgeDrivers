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

local lock_constants = (require "lock_constants")
local json = require "dkjson"

local get_lock_codes = function(device)
  return device:get_field(lock_constants.LOCK_CODES) or {}
end

local lock_codes_event = function(device, lock_codes)
  device:set_field(lock_constants.LOCK_CODES, lock_codes)
  device:emit_event(capabilities.lockCodes.lockCodes(json.encode(lock_codes)))
end

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
  if (device:get_field(lock_constants.CHECKING_CODE) == nil) then device:set_field(lock_constants.CHECKING_CODE, 1) end
  device:emit_event(LockCodes.scanCodes("Scanning"))
  device:send(LockCluster.server.commands.GetPINCode(device, device:get_field(lock_constants.CHECKING_CODE)))
end

local set_code = function(driver, device, command)
  if (command.args.codePIN == "") then
    driver:inject_capability_command(device, {
      capability = capabilities.lockCodes.ID,
      command = capabilities.lockCodes.commands.nameSlot.NAME,
      args = command.args,
      positional_args = command.positional_args
    })
  else
    device:send(LockCluster.server.commands.SetPINCode(device,
            command.args.codeSlot,
            UserStatusEnum.OCCUPIED_ENABLED,
            UserTypeEnum.UNRESTRICTED,
            command.args.codePIN)
    )
    if (command.args.codeName ~= nil) then
      -- wait for confirmation from the lock to commit this to memory
      -- Groovy driver has a lot more info passed here as a description string, may need to be investigated
      local codeState = device:get_field(lock_constants.CODE_STATE) or {}
      codeState["setCode"..command.args.codeSlot] = command.args.codePIN
      codeState["setName"..command.args.codeSlot] = command.args.codeName
      device:set_field(lock_constants.CODE_STATE, codeState)
    end
    device.thread:call_with_delay(4, function(d)
      device:send(LockCluster.server.commands.GetPINCode(device, command.args.codeSlot))
    end)
  end
end

local update_codes = function(driver, device, command)
  -- args.codes is json
  for name, code in pairs(command.args.codes) do
    -- these seem to come in the format "code[slot#]: code"
    local code_slot = tonumber(string.gsub(name, "code", ""), 10)
    if (code_slot ~= nil) then
      if (code ~= nil and code ~= "0") then
        device:send(LockCluster.server.commands.SetPINCode(device,
                code_slot,
                UserStatusEnum.OCCUPIED_ENABLED,
                UserTypeEnum.UNRESTRICTED,
                code)
        )
        device:send(LockCluster.server.commands.GetPINCode(device, code_slot))
      else
        device:send(LockCluster.client.commands.ClearPINCode(device, code_slot))
        device.thread:call_with_delay(2, function(d)
          device:send(LockCluster.server.commands.GetPINCode(device, code_slot))
        end)
      end
    end
  end
end

local get_code_name = function(device, code_id)
  if (device:get_field(lock_constants.CODE_STATE) ~= nil and device:get_field(lock_constants.CODE_STATE)["setName"..code_id] ~= nil) then
    -- this means a code set operation succeeded
    return device:get_field(lock_constants.CODE_STATE)["setName"..code_id]
  elseif (get_lock_codes(device)[code_id] ~= nil) then
    return get_lock_codes(device)[code_id]
  else
    return "Code " .. code_id
  end
end

local get_change_type = function(device, code_id)
  if (get_lock_codes(device)[code_id] == nil) then
    return " set"
  else
    return " changed"
  end
end

local code_deleted = function(device, code_slot)
  local codeState = device:get_field(lock_constants.CODE_STATE)
  if (codeState ~= nil) then
    codeState["setName".. code_slot] = nil
    codeState["setCode".. code_slot] = nil
    device:set_field(lock_constants.CODE_STATE, codeState)
  end

  local lock_codes = get_lock_codes(device)
  local event = LockCodes.codeChanged(code_slot.." deleted")
  event.data = {codeName = get_code_name(device, code_slot)}
  lock_codes[code_slot] = nil
  device:emit_event(event)
  return lock_codes
end

local get_pin_response_handler = function(driver, device, zb_mess)
  local event = LockCodes.codeChanged("")
  local code_slot = tostring(zb_mess.body.zcl_body.user_id.value)
  local localCode = device:get_field(lock_constants.CODE_STATE)
  if localCode ~= nil then localCode = localCode["setCode"..code_slot] end
  local code_name = get_code_name(device, code_slot)
  local lock_codes = get_lock_codes(device)
  event.data = {codeName = code_name}
  if (zb_mess.body.zcl_body.user_status.value == UserStatusEnum.OCCUPIED_ENABLED) then
    -- Code slot is occupied
    if (localCode ~= nil) then
      local serverCode = zb_mess.body.zcl_body.code.value
      if (localCode == serverCode) then
        event.value = code_slot .. get_change_type(device, code_slot)
        device:emit_event(event)
        lock_codes[code_slot] = code_name
        lock_codes_event(device, lock_codes)
      else
        event.value = code_slot .. " failed"
        event.data = nil
        device:emit_event(event)
      end
    else
      local change_type = get_change_type(device, code_slot)
      event.value = code_slot .. get_change_type(device, code_slot)
      device:emit_event(event)
      lock_codes[code_slot] = code_name
      lock_codes_event(device, lock_codes)
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
    elseif (lock_codes[code_slot] ~= nil) then
      -- Code has been deleted
      lock_codes_event(device, (code_deleted(device, code_slot)))
    else
      -- Code is unset
      event.value = code_slot .. " unset"
      device:emit_event(event)
    end
  end

  code_slot = tonumber(code_slot)
  if (code_slot == device:get_field(lock_constants.CHECKING_CODE)) then
    -- the code we're checking has arrived
    local defaultMaxCodes = 8
    if (code_slot >= defaultMaxCodes) then
      device:emit_event(LockCodes.scanCodes("Complete"))
      device:set_field(lock_constants.CHECKING_CODE, nil)
    else
      local checkingCode = device:get_field(lock_constants.CHECKING_CODE) + 1
      device:set_field(lock_constants.CHECKING_CODE, checkingCode)
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
      [LockCodes.commands.updateCodes.NAME] = update_codes,
      [LockCodes.commands.reloadAllCodes.NAME] = reload_all_codes,
      [LockCodes.commands.setCode.NAME] = set_code,
    }
  },

  sub_drivers = { require("yale.yale-bad-battery-reporter") },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "ASSA ABLOY iRevo" or device:get_manufacturer() == "Yale"
  end
}

return yale_door_lock_driver
