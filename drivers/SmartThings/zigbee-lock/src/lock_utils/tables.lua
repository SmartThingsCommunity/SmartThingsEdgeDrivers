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

-- Add an entry to a named table. The entry must satisfy all required_keys for
-- that table. An entry whose match_key value already exists in the
-- table is skipped to prevent duplicates. If the table has a max_entries limit,
-- entries that exceed the limit are not added.
function table_utils.add_entry(device, table_name, entry)
  device.log.debug("table_helpers: attempting to add entry " .. st_utils.stringify_table(entry) .. " to " .. table_name)
  local def = resolve_table_def(device, table_name)
  if not def then return COMMAND_RESULT.FAILURE end
  if not validate_entry(device, entry, def.required_keys) then return COMMAND_RESULT.FAILURE end
  local t = table_utils.get_state(device, def)
  if not t then return COMMAND_RESULT.FAILURE end

  if #t >= table_utils.get_max_entries(device, table_name) then
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
  device:emit_event(def.attribute({}, {visibility = {displayed = false}}))
  persist_table(device, def, {})
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
