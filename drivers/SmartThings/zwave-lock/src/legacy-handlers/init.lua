-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local cc = require "st.zwave.CommandClass"
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local UserCode = (require "st.zwave.CommandClass.UserCode")({version=1})
local LockDefaults = require "st.zwave.defaults.lock"
local LockCodesDefaults = require "st.zwave.defaults.lockCodes"

local init_handler = function(driver, device, event)
  local constants = require "st.zwave.constants"
  -- temp fix before this can be changed from being persisted in memory
  device:set_field(constants.CODE_STATE, nil, { persist = true })
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
  device:emit_event(capabilities.lockCredentials.credentials(lock_credentials, { visibility = { displayed = false } }))
  device:emit_event(capabilities.lockUsers.users(lock_users, { visibility = { displayed = false } }))

  local code_length  = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.codeLength.NAME)
  if code_length then
    device:emit_event(capabilities.lockCredentials.minPinCodeLen(code_length, { visibility = { displayed = false } }))
    device:emit_event(capabilities.lockCredentials.maxPinCodeLen(code_length, { visibility = { displayed = false } }))
  end

  local max_codes = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME)
  if max_codes then
    device:emit_event(capabilities.lockCredentials.pinUsersSupported(max_codes, { visibility = { displayed = false } }))
    device:emit_event(capabilities.lockUsers.totalUsersSupported(max_codes, { visibility = { displayed = false } }))
  else
    -- if we don't have a code length, request it from the device
    device:send(UserCode:UsersNumberGet({}))
  end

  device:emit_event(capabilities.lockCredentials.supportedCredentials({"pin"}, { visibility = { displayed = false } }))
  device:emit_event(capabilities.lockCodes.migrated(true, { visibility = { displayed = false } }))
  local consts = require("lock_utils.constants")

  device:set_field(consts.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true }) -- persist the migrated state to the datastore
end

local legacy_capabilities = {
  supported_capabilities = {
    capabilities.lock,
    capabilities.lockCodes,
    capabilities.battery,
    capabilities.tamperAlert
  },
  lifecycle_handlers = {
    init = init_handler,
  },
  capability_handlers = {
    [capabilities.lockCodes.ID] = {
      [capabilities.lockCodes.commands.updateCodes.NAME] = update_codes,
      [capabilities.lockCodes.commands.migrate.NAME] = migrate
    },
  },
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = function(driver, device, cmd)
        LockDefaults.zwave_handlers[cc.NOTIFICATION][Notification.REPORT](driver, device, cmd)
        LockCodesDefaults.zwave_handlers[cc.NOTIFICATION][Notification.REPORT](driver, device, cmd)
        local TamperDefaults = require "st.zwave.defaults.tamperAlert"
        TamperDefaults.zwave_handlers[cc.NOTIFICATION][Notification.REPORT](driver, device, cmd)
      end
    },
    [cc.USER_CODE] = {
      [UserCode.REPORT] = LockCodesDefaults.zwave_handlers[cc.USER_CODE][UserCode.REPORT],
      [UserCode.USERS_NUMBER_REPORT] = LockCodesDefaults.zwave_handlers[cc.USER_CODE][UserCode.USERS_NUMBER_REPORT],
    }
  },
  sub_drivers = require("legacy-handlers.sub_drivers"),
  can_handle = require("legacy-handlers.can_handle"),
  NAME = "legacy-handlers"
}

return legacy_capabilities
