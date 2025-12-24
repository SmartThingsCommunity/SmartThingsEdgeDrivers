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

local capabilities = require "st.capabilities"

local SCAN_CODES_CHECK_INTERVAL = 30

local function periodic_codes_state_verification(driver, device)
  local scan_codes_state = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.scanCodes.NAME)
  if scan_codes_state == "Scanning" then
    driver:inject_capability_command(device,
            { capability = capabilities.lockCodes.ID,
              command = capabilities.lockCodes.commands.reloadAllCodes.NAME,
              args = {}
            }
    )
    device.thread:call_with_delay(
      SCAN_CODES_CHECK_INTERVAL,
      function(d)
        periodic_codes_state_verification(driver, device)
      end
    )
  end
end

local init_handler = function(driver, device, event)
  local constants = require "st.zwave.constants"
  -- temp fix before this can be changed from being persisted in memory
  device:set_field(constants.CODE_STATE, nil, { persist = true })
end

--- Builds up initial state for the device
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
local function added_handler(self, device)
  self:inject_capability_command(device,
      { capability = capabilities.lockCodes.ID,
        command = capabilities.lockCodes.commands.reloadAllCodes.NAME,
        args = {} })
  device.thread:call_with_delay(
      SCAN_CODES_CHECK_INTERVAL,
      function(d)
        periodic_codes_state_verification(self, device)
      end
  )
  local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
  local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
  device:send(DoorLock:OperationGet({}))
  device:send(Battery:Get({}))
  if (device:supports_capability(capabilities.tamperAlert)) then
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  end
end

--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd table
local function update_codes(driver, device, cmd)
  local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
  local delay = 0
  -- args.codes is json
  for name, code in pairs(cmd.args.codes) do
    -- these seem to come in the format "code[slot#]: code"
    local code_slot = tonumber(string.gsub(name, "code", ""), 10)
    if (code_slot ~= nil) then
      if (code ~= nil and (code ~= "0" and code ~= "")) then
        -- code changed
        device.thread:call_with_delay(delay, function ()
          device:send(UserCode:Set({
            user_identifier = code_slot,
            user_code = code,
            user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS}))
        end)
        delay = delay + 2.2
      else
        -- code deleted
        device.thread:call_with_delay(delay, function ()
          device:send(UserCode:Set({user_identifier = code_slot, user_id_status = UserCode.user_id_status.AVAILABLE}))
        end)
        delay = delay + 2.2
        device.thread:call_with_delay(delay, function ()
          device:send(UserCode:Get({user_identifier = code_slot}))
        end)
        delay = delay + 2.2
      end
    end
  end
end

--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd table
local function migrate(driver, device, cmd)
  local LockCodesDefaults = require "st.zwave.defaults.lockCodes"
  local get_lock_codes = LockCodesDefaults.get_lock_codes
  local lock_users = {}
  local lock_credentials = {}
  local lock_codes = get_lock_codes(device)
  local ordered_codes = {}

  for code in pairs(lock_codes) do
    table.insert(ordered_codes, code)
  end

  table.sort(ordered_codes)
  for index = 1, #ordered_codes do
    local code_slot, code_name = ordered_codes[index], lock_codes[ ordered_codes[index] ]
    table.insert(lock_users, {userIndex = index, userType = "guest", userName = code_name})
    table.insert(lock_credentials, {userIndex = index, credentialIndex = tonumber(code_slot), credentialType = "pin"})
  end

  local code_length  = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.codeLength.NAME)
  local min_code_len = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.minCodeLength.NAME, 4)
  local max_code_len = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodeLength.NAME, 10)
  local max_codes    = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME, 8)
  if (code_length ~= nil) then
    max_code_len = code_length
    min_code_len = code_length
  end

  device:emit_event(capabilities.lockCredentials.minPinCodeLen(min_code_len, { visibility = { displayed = false } }))
  device:emit_event(capabilities.lockCredentials.maxPinCodeLen(max_code_len, { visibility = { displayed = false } }))
  device:emit_event(capabilities.lockCredentials.pinUsersSupported(max_codes, { visibility = { displayed = false } }))
  device:emit_event(capabilities.lockCredentials.credentials(lock_credentials, { state_change = true, visibility = { displayed = true } }))
  device:emit_event(capabilities.lockCredentials.supportedCredentials({"pin"}, { visibility = { displayed = false } }))
  device:emit_event(capabilities.lockUsers.totalUsersSupported(max_codes, { visibility = { displayed = false } }))
  device:emit_event(capabilities.lockUsers.users(lock_users, { state_change = true, visibility = { displayed = true } }))
  device:emit_event(capabilities.lockCodes.migrated(true, { state_change = true,  visibility = { displayed = true } }))
end

local using_old_capabilities = {
  supported_capabilities = {
    capabilities.lock,
    capabilities.lockCodes,
    capabilities.battery,
    capabilities.tamperAlert
  },
  lifecycle_handlers = {
    init = init_handler,
    added = added_handler,
  },
  capability_handlers = {
    [capabilities.lockCodes.ID] = {
      [capabilities.lockCodes.commands.updateCodes.NAME] = update_codes,
      [capabilities.lockCodes.commands.migrate.NAME] = migrate
    },
  },
  sub_drivers = {
    require("using-old-capabilities.zwave-alarm-v1-lock"),
    require("using-old-capabilities.schlage-lock"),
    require("using-old-capabilities.samsung-lock"),
    require("using-old-capabilities.keywe-lock"),
  },
  can_handle = function(opts, driver, device, ...)
    if not device:supports_capability_by_id(capabilities.lockCodes.ID) then return false end
    local lock_codes_migrated = device:get_latest_state("main", capabilities.lockCodes.ID,
      capabilities.lockCodes.migrated.NAME, false)
    if not lock_codes_migrated then
      local subdriver = require("using-old-capabilities")
      return true, subdriver
    end
    return false
  end,
  NAME = "Using old capabilities"
}

return using_old_capabilities
