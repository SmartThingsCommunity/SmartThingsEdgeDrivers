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
local utils = require "st.utils"
local capabilities = require "st.capabilities"
local json = require "st.json"
local LockCodes = capabilities.lockCodes


local lock_utils =  {
  -- Constants
  LOCK_CODES      = "lockCodes",
  CHECKING_CODE   = "checkingCode",
  CODE_STATE      = "codeState",
  MIGRATION_COMPLETE = "migrationComplete",
  MIGRATION_RELOAD_SKIPPED = "migrationReloadSkipped",
  CHECKED_CODE_SUPPORT = "checkedCodeSupport"
}

lock_utils.get_lock_codes = function(device)
  local lc = device:get_field(lock_utils.LOCK_CODES)
  return lc ~= nil and lc or {}
end

lock_utils.lock_codes_event = function(device, lock_codes)
  device:set_field(lock_utils.LOCK_CODES, lock_codes, { persist = true } )
  device:emit_event(capabilities.lockCodes.lockCodes(json.encode(utils.deep_copy(lock_codes)), { visibility = { displayed = false } }))
end


function lock_utils.get_code_name(device, code_id)
  if (device:get_field(lock_utils.CODE_STATE) ~= nil and device:get_field(lock_utils.CODE_STATE)["setName"..code_id] ~= nil) then
    -- this means a code set operation succeeded
    return device:get_field(lock_utils.CODE_STATE)["setName"..code_id]
  elseif (lock_utils.get_lock_codes(device)[code_id] ~= nil) then
    return lock_utils.get_lock_codes(device)[code_id]
  else
    return "Code " .. code_id
  end
end

function lock_utils.get_change_type(device, code_id)
  if (lock_utils.get_lock_codes(device)[code_id] == nil) then
    return " set"
  else
    return " changed"
  end
end

function lock_utils.reset_code_state(device, code_slot)
  local codeState = device:get_field(lock_utils.CODE_STATE)
  if (codeState ~= nil) then
    codeState["setName".. code_slot] = nil
    codeState["setCode".. code_slot] = nil
    device:set_field(lock_utils.CODE_STATE, codeState, { persist = true })
  end
end

function lock_utils.code_deleted(device, code_slot)
  local lock_codes = lock_utils.get_lock_codes(device)
  local event = LockCodes.codeChanged(code_slot.." deleted", { state_change = true })
  event.data = {codeName = lock_utils.get_code_name(device, code_slot)}
  lock_codes[code_slot] = nil
  device:emit_event(event)
  lock_utils.reset_code_state(device, code_slot)
  return lock_codes
end

function lock_utils.populate_state_from_data(device)
  if device.data.lockCodes ~= nil and device:get_field(lock_utils.MIGRATION_COMPLETE) ~= true then
    -- build the lockCodes table
    local lockCodes = {}
    local lc_data = json.decode(device.data.lockCodes)
    for k, v in pairs(lc_data) do
      lockCodes[k] = v
    end
    -- Populate the devices `lockCodes` field
    device:set_field(lock_utils.LOCK_CODES, utils.deep_copy(lockCodes), { persist = true })
    -- Populate the devices state history cache
    device.state_cache["main"] = device.state_cache["main"] or {}
    device.state_cache["main"][capabilities.lockCodes.ID] = device.state_cache["main"][capabilities.lockCodes.ID] or {}
    device.state_cache["main"][capabilities.lockCodes.ID][capabilities.lockCodes.lockCodes.NAME] = {value = json.encode(utils.deep_copy(lockCodes))}

    device:set_field(lock_utils.MIGRATION_COMPLETE, true, { persist = true })
  end
end

return lock_utils
