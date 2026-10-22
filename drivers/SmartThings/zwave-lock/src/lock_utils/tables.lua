-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities   = require "st.capabilities"
local st_utils       = require "st.utils"
local COMMAND_RESULT = require "lock_utils.constants".COMMAND_RESULT

local table_utils = {}

-- DEFS describes how each capability-backed state table is structured:
--
--   capability        SmartThings capability (used for device support checks and to get latest state)
--   attribute         Capability attribute function (used to emit state)
--   max_entries       Attribute of the capability that defines the maximum number of entries allowed in the table
--   match_key         Key used to identify entries in flat tables
--   required_keys     Keys that must be non-nil when adding an entry
--   persistent_field  device:set_field key used to back up the table across restarts
--

local DEFS = {
  users = {
    capability       = capabilities.lockUsers,
    attribute        = capabilities.lockUsers.users,
    max_entries      = capabilities.lockUsers.totalUsersSupported,
    match_key        = "userIndex",
    required_keys    = {"userIndex", "userType"},
    persistent_field = "persistedUsers",
  },
  credentials = {
    capability       = capabilities.lockCredentials,
    attribute        = capabilities.lockCredentials.credentials,
    max_entries      = capabilities.lockCredentials.pinUsersSupported,
    match_key        = "credentialIndex",
    required_keys    = {"userIndex", "credentialIndex", "credentialType"},
    persistent_field = "persistedCredentials",
  }
}

-- Yale locks report their "master code" in this user code slot.
local YALE_MANUFACTURER_ID = 0x0129
local YALE_MASTER_CREDENTIAL_INDEX = 251

-- Returns the credentialIndex of the device's master code slot, or nil if the device is not a Yale lock.
function table_utils.master_credential_index(device)
  if device.zwave_manufacturer_id == YALE_MANUFACTURER_ID then
    return YALE_MASTER_CREDENTIAL_INDEX
  end
end

-- Resolve a table name to its definition. Logs an error and returns nil if unknown.
local function resolve_table_def(device, table_name)
  local def = DEFS[table_name]
  if not def then
    device.log.error(string.format("table_helpers: unknown table %q", table_name))
  end
  return def
end

-- Validate that an entry table contains all required keys.
local function validate_entry(device, entry, required_keys)
  for _, key in ipairs(required_keys or {}) do
    if entry[key] == nil then
      device.log.error(string.format("table_helpers: entry missing required key %q", key))
      return false
    end
  end
  return true
end

-- Write the current table contents to the device's persistent field store so that
-- the state survives driver restarts and can be restored if the capability state
-- cache is wiped.
local function persist_table(device, def, data)
  device:set_field(def.persistent_field, st_utils.deep_copy(data), { persist = true })
end

-- Read the current state for a table and return a deep-copied array.
-- Accepts either a string table name ("users", "credentials") or a DEFS entry directly.
-- Returns nil (with a warning) if the capability is unsupported by the device.
-- When the capability state cache has been wiped (get_latest_state returns nil),
-- falls back to the persistent field store so that callers always receive the
-- last-known state rather than an empty table.
--- @return table[] | nil
function table_utils.get_state(device, name_or_def)
  local def = type(name_or_def) == "string" and resolve_table_def(device, name_or_def) or name_or_def
  if not def then return nil end
  if not device:supports_capability(def.capability, "main") then
    device.log.warn(string.format(
      "table_helpers: device does not support capability %q", def.capability.ID
    ))
    return
  end
  local state = device:get_latest_state("main", def.capability.ID, def.attribute.NAME)
  if state ~= nil then
    return st_utils.deep_copy(state)
  end
  -- Capability state cache is absent (e.g. after a hub reboot); fall back to the
  -- persistent store so that callers see the last-known table contents.
  return st_utils.deep_copy(device:get_field(def.persistent_field) or {})
end

-- Find an entry in a named table where the match_key equals value.
-- Returns the matching entry, or nil if not found.
function table_utils.find_entry(device, table_name, value)
  local def = resolve_table_def(device, table_name)
  if not def then return nil end
  local t = table_utils.get_state(device, def)
  if not t then return nil end
  for _, entry in ipairs(t) do
    if entry[def.match_key] == value then return entry end
  end
  return nil
end

-- Find an entry in a named table where entry[key] equals value (arbitrary key search).
-- Returns the matching entry, or nil if not found.
function table_utils.find_entry_by(device, table_name, key, value)
  local def = resolve_table_def(device, table_name)
  if not def then return nil end
  local t = table_utils.get_state(device, def)
  if not t then return nil end
  for _, entry in ipairs(t) do
    if entry[key] == value then return entry end
  end
  return nil
end

-- Find all entries in a named table where entry[key] equals value (arbitrary key search).
-- Returns an array of matching entries, or an empty array if none found.
function table_utils.find_all_entries_by(device, table_name, key, value)
  local def = resolve_table_def(device, table_name)
  if not def then return {} end
  local t = table_utils.get_state(device, def)
  if not t then return {} end
  local matches = {}
  for _, entry in ipairs(t) do
    if entry[key] == value then table.insert(matches, entry) end
  end
  return matches
end

-- Return the lowest positive integer not yet used as the match_key in the named table.
-- Used to auto-assign the next available slot for a new entry.
function table_utils.next_index(device, table_name)
  local def = resolve_table_def(device, table_name)
  if not def then return 1 end
  local t = table_utils.get_state(device, def) or {}
  local occupied = {}
  for _, entry in ipairs(t) do occupied[entry[def.match_key]] = true end
  local idx = 1
  while occupied[idx] do idx = idx + 1 end
  return idx
end

function table_utils.get_max_entries(device, table_name)
  local def = resolve_table_def(device, table_name)
  if not def then return end
  return device:get_latest_state("main", def.capability.ID, def.max_entries.NAME, 20) -- arbitrary, default to 20 if the attribute is missing
end

-- The user index that owns the master code. This is offset from the lock's max users supported:
-- 1 puts it just past the last real user slot (never colliding with a real user). 0 puts it on the last user slot,
-- which stays within the supported range, but shares a user with a real credential in that slot if it is in use.
-- TEMPORARY: set to 0 to test whether clients hide users with an index past totalUsersSupported.
local MASTER_USER_INDEX_OFFSET = 0

function table_utils.master_user_index(device)
  return table_utils.get_max_entries(device, "users") + MASTER_USER_INDEX_OFFSET
end


-- Return the credential entry for the master code, if the device has one in its table (Yale only).
local function find_master_credential(device)
  local master_index = table_utils.master_credential_index(device)
  return master_index ~= nil and table_utils.find_entry(device, "credentials", master_index) or nil
end

-- Return true if the entry is the master code credential, or the user that owns it.
local function is_master_entry(device, table_name, entry, master_cred)
  if table_name == "credentials" then
    return entry.credentialIndex == table_utils.master_credential_index(device)
  end
  return master_cred ~= nil and entry.userIndex == master_cred.userIndex
end

-- Return true if the user index belongs to the user that owns the master code credential.
function table_utils.is_master_user(device, user_index)
  local master_cred = find_master_credential(device)
  return master_cred ~= nil and master_cred.userIndex == user_index
end

-- Return true if the credential index is the master code credential (Yale only).
function table_utils.is_master_credential(device, credential_index)
  local master_index = table_utils.master_credential_index(device)
  return master_index ~= nil and master_index == credential_index
end

-- Return true if the named table has reached its max_entries limit. The master code credential (Yale only),
-- and the user that owns it, are not one of the lock's user slots, so they do not count toward the limit.
function table_utils.is_full(device, table_name)
  local def = resolve_table_def(device, table_name)
  if not def then return true end
  local master_cred = find_master_credential(device)
  local count = 0
  for _, entry in ipairs(table_utils.get_state(device, def) or {}) do
    if not is_master_entry(device, table_name, entry, master_cred) then count = count + 1 end
  end
  return count >= table_utils.get_max_entries(device, table_name)
end

-- Add an entry to a named table. The entry must satisfy all required_keys for
-- that table. An entry whose match_key value already exists in the
-- table is skipped to prevent duplicates. If the table has a max_entries limit,
-- entries that exceed the limit are not added, unless exempt_from_limit is true (used for the master code).
function table_utils.add_entry(device, table_name, entry, exempt_from_limit)
  device.log.debug("table_helpers: attempting to add entry " .. st_utils.stringify_table(entry) .. " to " .. table_name)
  local def = resolve_table_def(device, table_name)
  if not def then return COMMAND_RESULT.FAILURE end
  if not validate_entry(device, entry, def.required_keys) then return COMMAND_RESULT.FAILURE end
  local t = table_utils.get_state(device, def)
  if not t then return COMMAND_RESULT.FAILURE end

  if not exempt_from_limit and table_utils.is_full(device, table_name) then
    device.log.warn(string.format(
      "table_helpers: cannot add entry to %q, max entries reached", table_name
    ))
    return COMMAND_RESULT.RESOURCE_EXHAUSTED
  end

  -- Object entry: skip if an entry with the same match_key value already exists
  if def.match_key then
    for _, existing in ipairs(t) do
      if existing[def.match_key] == entry[def.match_key] then
        device.log.warn(string.format(
          "table_helpers: entry with %s == %s already exists in %q, skipping",
          def.match_key, tostring(entry[def.match_key]), table_name
        ))
        return COMMAND_RESULT.OCCUPIED
      end
    end
  end

  table.insert(t, st_utils.deep_copy(entry))

  device:emit_event(def.attribute(t, {visibility = {displayed = false}}))
  persist_table(device, def, t)
  return COMMAND_RESULT.SUCCESS
end


--- Update fields of an existing entry in a table.
--- The entry to update is identified by the match_key parameter in DEFS.
function table_utils.update_entry(device, table_name, match_value, updates)
  device.log.debug("table_helpers: attempting to update entry " .. match_value .. " in " .. table_name .. ": " .. st_utils.stringify_table(updates))
  local def = resolve_table_def(device, table_name)
  if not def then return COMMAND_RESULT.FAILURE end
  local t = table_utils.get_state(device, def)
  if not t then return COMMAND_RESULT.FAILURE end

  for _, entry in ipairs(t) do
    if entry[def.match_key] == match_value then
      for k, v in pairs(updates) do
        entry[k] = v
      end
      device:emit_event(def.attribute(t, {visibility = {displayed = false}}))
      persist_table(device, def, t)
      return COMMAND_RESULT.SUCCESS
    end
  end

  device.log.warn(string.format(
    "table_helpers: no entry found in %q with %s == %s",
    table_name, def.match_key, tostring(match_value)
  ))
  return COMMAND_RESULT.FAILURE
end


-- Delete an entry from a table.
--
-- Returns SUCCESS, or FAILURE if nothing matched.
function table_utils.delete_entry(device, table_name, matcher)
  device.log.debug("table_helpers: attempting to delete entry " .. matcher .. " from " .. table_name)
  local def = resolve_table_def(device, table_name)
  if not def then return COMMAND_RESULT.FAILURE end
  local t = table_utils.get_state(device, def)
  if not t then return COMMAND_RESULT.FAILURE end

  local predicate = function(entry) return entry[def.match_key] == matcher end

  for i, entry in ipairs(t) do
    if predicate(entry) then
      table.remove(t, i)
      device:emit_event(def.attribute(t, {visibility = {displayed = false}}))
      persist_table(device, def, t)
      return COMMAND_RESULT.SUCCESS
    end
  end
  return COMMAND_RESULT.FAILURE
end

-- Delete all entries from a table.
function table_utils.delete_all_entries(device, table_name)
  device.log.debug("table_helpers: attempting to delete all entries from " .. table_name)
  local def = resolve_table_def(device, table_name)
  if not def then return COMMAND_RESULT.FAILURE end
  -- The master code (Yale only) is not removed by a delete-all, so its entries are kept.
  local master_cred = find_master_credential(device)
  local remaining = {}
  for _, entry in ipairs(table_utils.get_state(device, def) or {}) do
    if is_master_entry(device, table_name, entry, master_cred) then table.insert(remaining, entry) end
  end
  device:emit_event(def.attribute(remaining, {visibility = {displayed = false}}))
  persist_table(device, def, remaining)
  return COMMAND_RESULT.SUCCESS
end

-- Restore capability state from the persistent field store.
-- Called during init to re-emit table events if the capability state cache
-- has been wiped (e.g. after a hub reboot). Only emits for tables that have
-- persisted data, are in a nil state, and whose capability is supported by the device.
function table_utils.restore_from_persistent_store(device)
  for _, internal in pairs(DEFS) do
    if device:supports_capability(internal.capability, "main") and
      device:get_latest_state("main", internal.capability.ID, internal.attribute.NAME) == nil
    then
      local persisted = st_utils.deep_copy(device:get_field(internal.persistent_field))
      if persisted and #persisted > 0 then
        device:emit_event(internal.attribute(persisted, {visibility = {displayed = false}}))
      end
    end
  end
end

return table_utils
