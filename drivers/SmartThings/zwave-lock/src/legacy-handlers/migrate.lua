-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local LockCodesDefaults = require "st.zwave.defaults.lockCodes"

local consts      = require "lock_utils.constants"
local table_utils = require "lock_utils.tables"

-- Migrate the lock's lockCodes state to lockUsers and lockCredentials. This is shared by the lockCodes.migrate
-- handlers of the legacy sub-drivers, which pass the admin code slot for a lock that has one.
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param admin_index number|nil the credentialIndex of the lock's admin code slot, or nil if it has none
local function migrate_codes(driver, device, admin_index)
  local get_lock_codes = LockCodesDefaults.get_lock_codes
  local lock_users = {}
  local lock_credentials = {}
  local lock_codes = get_lock_codes(device)
  local ordered_codes = {}

  -- Slots that are not valid credential indices (e.g. 0, which means "all users" in Z-Wave, or non-numeric)
  -- are dropped rather than migrated.
  local min_credential = table_utils.get_minimum(device, "credentials")
  for code_slot in pairs(lock_codes) do
    local credential_index = tonumber(code_slot)
    if math.type(credential_index) == "integer" and credential_index >= min_credential then
      table.insert(ordered_codes, {slot = code_slot, index = credential_index})
    else
      device.log.warn(string.format("Dropping lock code slot %q during migration: not a valid credential index", tostring(code_slot)))
    end
  end

  table.sort(ordered_codes, function(a, b) return a.index < b.index end)
  -- userIndex is assigned sequentially from 1 so every user is valid and unique, except that the admin code's
  -- user takes the admin code slot as its index.
  local user_index = 0
  for _, code in ipairs(ordered_codes) do
    local is_admin = admin_index ~= nil and code.index == admin_index
    if not is_admin then
      user_index = user_index + 1
      if admin_index ~= nil and user_index == admin_index then user_index = user_index + 1 end
    end
    local owner_index = is_admin and code.index or user_index
    table.insert(lock_users, {
      userIndex = owner_index,
      userType = is_admin and consts.ADMIN.USER_TYPE or "guest",
      userName = lock_codes[code.slot],
    })
    table.insert(lock_credentials, {userIndex = owner_index, credentialIndex = code.index, credentialType = "pin"})
  end
  device:emit_event(capabilities.lockCredentials.credentials(lock_credentials, { visibility = { displayed = false } }))
  device:emit_event(capabilities.lockUsers.users(lock_users, { visibility = { displayed = false } }))

  -- lockCodes tracks a single fixed code length, which only some locks (e.g. Schlage) report.
  -- Without one, fall back to the Z-Wave spec default range so the bounds are always set.
  local code_length  = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.codeLength.NAME)
  local min_pin_length = code_length or consts.DEFAULT_MIN_PIN_LENGTH
  local max_pin_length = code_length or consts.DEFAULT_MAX_PIN_LENGTH
  device:emit_event(capabilities.lockCredentials.minPinCodeLen(min_pin_length, { visibility = { displayed = false } }))
  device:emit_event(capabilities.lockCredentials.maxPinCodeLen(max_pin_length, { visibility = { displayed = false } }))

  local max_codes = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME)
  if max_codes then
    device:emit_event(capabilities.lockCredentials.pinUsersSupported(max_codes, { visibility = { displayed = false } }))
    device:emit_event(capabilities.lockUsers.totalUsersSupported(max_codes, { visibility = { displayed = false } }))
  end

  device:emit_event(capabilities.lockCredentials.supportedCredentials({"pin"}, { visibility = { displayed = false } }))
  device:emit_event(capabilities.lockCodes.migrated(true, { visibility = { displayed = false } }))

  device:set_field(consts.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true }) -- persist the migrated state to the datastore

  driver:inject_capability_command(device, {
    capability = capabilities.refresh.ID,
    command = capabilities.refresh.commands.refresh.NAME,
    args = {}
  })
end

return migrate_codes
