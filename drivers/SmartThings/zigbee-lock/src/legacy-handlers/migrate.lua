-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities          = require "st.capabilities"
local lock_utils            = require "legacy-handlers.legacy_lock_utils"
local post_migration_consts = require "lock_utils.constants"
local table_utils           = require "lock_utils.tables"

local LockCodes       = capabilities.lockCodes
local LockUsers       = capabilities.lockUsers
local LockCredentials = capabilities.lockCredentials

-- Migrate lockCodes state to lockUsers/lockCredentials.
-- `master_code_slot` is the lockCodes slot, if any, known to hold a master code on this device. It is migrated
-- as a master code user rather than a guest.
return function(driver, device, command, master_code_slot)
  -- set supported credentials
  device:emit_event(LockCredentials.supportedCredentials({ post_migration_consts.CRED_TYPE_PIN }, { visibility = { displayed = false } }))

  -- migrate max/min credential length
  local cached_min_code_len = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.minCodeLength.NAME)
  local cached_max_code_len = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodeLength.NAME)
  if cached_min_code_len then
    device:emit_event(LockCredentials.minPinCodeLen(cached_min_code_len, { visibility = { displayed = false } }))
  end
  if cached_max_code_len then
    device:emit_event(LockCredentials.maxPinCodeLen(cached_max_code_len, { visibility = { displayed = false } }))
  end

  -- migrate total codes supported. maxCodes holds NumberOfPINUsersSupported, and PIN user IDs run from 0 to that
  -- value inclusive, so there is one more slot than reported.
  local cached_max_codes = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME)
  if cached_max_codes then
    device:emit_event(LockCredentials.pinUsersSupported(cached_max_codes + 1, { visibility = { displayed = false } }))
    device:emit_event(LockUsers.totalUsersSupported(cached_max_codes + 1, { visibility = { displayed = false } }))
  end

  -- migrate stored lock codes slots and user names
  local users, credentials = {}, {}
  local cached_lock_codes = lock_utils.get_lock_codes(device)
  local ordered_code_slots = {}
  local occupied_user_indices = {}
  local min_user = table_utils.get_minimum(device, "users")
  local min_credential = table_utils.get_minimum(device, "credentials")
  for code_slot_str, _ in pairs(cached_lock_codes) do
    local code_slot = tonumber(code_slot_str)
    -- Slots that are not valid credential indices are dropped rather than migrated.
    if math.type(code_slot) == "integer" and code_slot >= min_credential then
      table.insert(ordered_code_slots, code_slot)
      if code_slot >= min_user then occupied_user_indices[code_slot] = true end
    end
  end
  table.sort(ordered_code_slots)
  local next_free_user_index = min_user
  for _, code_slot in ipairs(ordered_code_slots) do
    local code_name = cached_lock_codes[tostring(code_slot)]
    -- A valid credential slot (e.g. 0) may not be a valid userIndex. Its user takes the lowest unused userIndex
    -- without displacing any slot whose number is already a valid userIndex.
    local user_index = code_slot
    if code_slot < min_user then
      while occupied_user_indices[next_free_user_index] do next_free_user_index = next_free_user_index + 1 end
      user_index = next_free_user_index
      occupied_user_indices[user_index] = true
    end
    -- cached_lock_codes is formatted as { ["1"] = "Guest 1", ["2"] = "Guest 2" }, etc
    local user_type = code_slot == master_code_slot and post_migration_consts.USER_TYPE_MASTER or "guest"
    table.insert(users, { userIndex = user_index, userType = user_type, userName = code_name })
    table.insert(credentials, { userIndex = user_index, credentialIndex = code_slot, credentialType = post_migration_consts.CRED_TYPE_PIN, credentialName = code_name })
  end
  -- manually ensure user/cred state is persisted, then emit events to populate the new capabilities with the migrated data.
  device:set_field("persistedUsers", users, { persist = true })
  device:set_field("persistedCredentials", credentials, { persist = true })
  device:emit_event(LockUsers.users(users, { visibility = { displayed = false } }))
  device:emit_event(LockCredentials.credentials(credentials, { visibility = { displayed = false } }))

  -- set and persist the migration complete flag and emit migrated event. Legacy subdriver will not be used again after this.
  device:emit_event(LockCodes.migrated(true, { visibility = { displayed = false } }))
  device:set_field(post_migration_consts.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })

  -- try to refresh all unstored state
  driver:inject_capability_command(device, {
    capability = capabilities.refresh.ID,
    command = capabilities.refresh.commands.refresh.NAME,
    args = {}
  })
end
