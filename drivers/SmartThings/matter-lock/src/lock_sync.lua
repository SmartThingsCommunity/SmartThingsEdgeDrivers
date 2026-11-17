-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Syncs the lockUsers/lockCredentials tables from the lock's user database.
-- Spec background:
-- * A User (for 1..NumberOfTotalUsersSupported) holds the name, status, type, and a list of the credentials it owns.
-- * A Credential is indexed per credential type (for PINs, 1..NumberOfPINUsersSupported) and is owned by exactly one user.

local capabilities = require "st.capabilities"
local clusters     = require "st.matter.clusters"
local im           = require "st.matter.interaction_model"
local lock_utils   = require "lock_utils"
local utils        = require "st.utils"
local version      = require "version"

if version.api < 10 then
  clusters.DoorLock = require "DoorLock"
end

local sync = {}

-- persisted; the user index currently being read
sync.USER_INDEX = "syncUserIndex"
-- persisted; holds the VERSION of the last completed sync
sync.USERS_SYNCED = "usersSynced"
-- bump to force every device to re-sync (a mismatch with usersSynced triggers it)
sync.VERSION = 1

-- lock_utils.COMMAND_NAME while a sync is in progress
local COMMAND_NAME = "syncUsersFromLock"
-- defined per spec
local MIN_USER_INDEX = 1
-- persisted; the VERSION under which USER_INDEX was started
local USER_INDEX_VERSION = "syncUserIndexVersion"
-- persisted; occupied users read from the lock so far in this pass
local REPORTED_USERS = "syncReportedUsers"
-- identifies the latest GetUser request, so the timeout of an earlier one is ignored
local REQUEST_TOKEN = "syncRequestToken"


function sync.is_syncing(device)
  return device:get_field(lock_utils.COMMAND_NAME) == COMMAND_NAME
end

-- Merge the users read off the lock into the lockUsers and lockCredentials tables.
local function merge_users(device, reported_users)
  local stored_users = device:get_latest_state(
    "main",
    capabilities.lockUsers.ID,
    capabilities.lockUsers.users.NAME,
    {}
  )
  local stored_creds = device:get_latest_state(
    "main",
    capabilities.lockCredentials.ID,
    capabilities.lockCredentials.credentials.NAME,
    {}
  )

  local stored_user_by_index, stored_cred_by_index, legacy_name_by_index = {}, {}, {}
  for _, user in ipairs(stored_users) do stored_user_by_index[user.userIndex] = user end
  for _, cred in ipairs(stored_creds) do
    if cred.credentialType == "pin" then stored_cred_by_index[cred.credentialIndex] = cred end
  end
  -- names from a lockCodes migration, keyed by PIN credential index
  for _, entry in ipairs(device:get_field(lock_utils.LOCK_CODES_FOR_MIGRATION) or {}) do
    local index = tonumber(entry[1])
    if index then legacy_name_by_index[index] = entry[2] end
  end

  -- the COTA credential's user is managed by the driver and should not be shown in the tables
  local users = {}
  for _, user in ipairs(reported_users) do
    local is_cota_user = false
    for _, pin in ipairs(user.pins or {}) do
      if pin ~= nil and pin == device:get_field(lock_utils.COTA_CRED_INDEX) then is_cota_user = true end
    end
    if not is_cota_user then table.insert(users, user) end
  end

  -- match each lock user to the stored user entry that holds its name
  local claimed, st_user_for = {}, {}
  for i, user in ipairs(users) do
    for _, pin in ipairs(user.pins or {}) do
      local stored_cred = stored_cred_by_index[pin]
      if stored_cred and stored_user_by_index[stored_cred.userIndex] and not claimed[stored_cred.userIndex] then
        claimed[stored_cred.userIndex] = true
        st_user_for[i] = stored_user_by_index[stored_cred.userIndex]
        break
      end
    end
  end
  for i, user in ipairs(users) do
    if st_user_for[i] == nil and stored_user_by_index[user.userIndex] and not claimed[user.userIndex] then
      claimed[user.userIndex] = true
      st_user_for[i] = stored_user_by_index[user.userIndex]
    end
    if st_user_for[i] == nil then
      for _, pin in ipairs(user.pins or {}) do
        if legacy_name_by_index[pin] then
          st_user_for[i] = {userName = legacy_name_by_index[pin], userType = "guest"}
          break
        end
      end
    end
  end

  local user_table, cred_table, read_user_indices = {}, {}, {}
  for i, user in ipairs(users) do
    local st_user = st_user_for[i]
    read_user_indices[user.userIndex] = true
    -- the stored/legacy name, else the name held by the lock, else a name made from the user index
    local user_name = st_user and st_user.userName or user.userName or string.format("Guest %d", user.userIndex)
    table.insert(user_table, {
      userIndex = user.userIndex,
      userName = user_name,
      userType = st_user and st_user.userType or "guest", -- the app requires migrated and synced users to default to guest
    })
    for _, pin in ipairs(user.pins or {}) do
      table.insert(cred_table, {
        userIndex = user.userIndex,
        credentialIndex = pin,
        credentialType = "pin",
        credentialName = stored_cred_by_index[pin] and stored_cred_by_index[pin].credentialName or legacy_name_by_index[pin] or user_name,
      })
    end
  end

  -- keep the entries of users that were not read
  for _, user in ipairs(stored_users) do
    if not read_user_indices[user.userIndex] then
      table.insert(user_table, {
        userIndex = user.userIndex,
        userName = user.userName,
        userType = user.userType
      })
    end
  end
  for _, cred in ipairs(stored_creds) do
    if not read_user_indices[cred.userIndex] then
      table.insert(cred_table, {
        userIndex = cred.userIndex,
        credentialIndex = cred.credentialIndex,
        credentialType = cred.credentialType,
        credentialName = cred.credentialName,
      })
    end
  end

  device:emit_event(capabilities.lockUsers.users(user_table, {visibility = {displayed = false}}))
  device:emit_event(capabilities.lockCredentials.credentials(cred_table, {visibility = {displayed = false}}))
end

local function clear_busy_state(device)
  device:set_field(lock_utils.COMMAND_NAME, nil, {persist = true})
  device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
end

local function finish_sync(device)
  merge_users(device, utils.deep_copy(device:get_field(REPORTED_USERS) or {}))
  device:set_field(sync.USER_INDEX, nil, {persist = true})
  device:set_field(REPORTED_USERS, nil, {persist = true})
  device:set_field(lock_utils.LOCK_CODES_FOR_MIGRATION, nil, {persist = true}) -- legacy names are now in the tables
  device:set_field(sync.USERS_SYNCED, sync.VERSION, {persist = true})
  clear_busy_state(device)
end

-- Ask the lock for the user at `index`.
local function request_user(device, index)
  device:set_field(sync.USER_INDEX, index, {persist = true})
  device:set_field(lock_utils.BUSY_STATE, os.time(), {persist = true}) -- keep the sync from expiring
  local token = (device:get_field(REQUEST_TOKEN) or 0) + 1
  device:set_field(REQUEST_TOKEN, token)

  local on_request_timeout = function()
    if device:get_field(REQUEST_TOKEN) ~= token or not sync.is_syncing(device) then return end
    device.log.warn_with({hub_logs = true}, string.format("No GetUserResponse for user index %s during sync, applying what has been read", device:get_field(sync.USER_INDEX)))
    merge_users(device, utils.deep_copy(device:get_field(REPORTED_USERS) or {}))
  end

  local timeout_s = 10
  device.thread:call_with_delay(timeout_s, function() on_request_timeout() end)
  device:send(clusters.DoorLock.server.commands.GetUser(device, device:component_to_endpoint("main"), index))
end

local function advance_walk(device, index)
  local max_users = device:get_latest_state("main", capabilities.lockUsers.ID, capabilities.lockUsers.totalUsersSupported.NAME)
  if max_users ~= nil and index > max_users then
    finish_sync(device)
    return
  end
  request_user(device, index)
end

-- The user at `index` could not be read. Move on so one bad user does not stall the sync.
local function handle_get_user_failure(device, index, reason)
  if device:get_latest_state("main", capabilities.lockUsers.ID, capabilities.lockUsers.totalUsersSupported.NAME) == nil then
    merge_users(device, utils.deep_copy(device:get_field(REPORTED_USERS) or {}))
    clear_busy_state(device)
    return
  end

  device.log.warn_with({hub_logs = true}, string.format("GetUser for user index %s failed during sync (%s), skipping it", index, reason))
  advance_walk(device, index + 1)
end

-- Start (or resume) syncing from the lock, if the device is not busy.
local function sync_users_from_lock(device)
  if not (device:supports_capability(capabilities.lockUsers) and device:supports_capability(capabilities.lockCredentials)) or
    device:get_field(sync.USERS_SYNCED) == sync.VERSION or
    lock_utils.is_busy_state_set(device) then
    return
  end

  -- progress from a sync begun under a different sync version is stale; start over.
  if device:get_field(USER_INDEX_VERSION) ~= sync.VERSION then
    device:set_field(sync.USER_INDEX, nil, {persist = true})
  end

  if device:get_field(sync.USER_INDEX) == nil then
    device:set_field(USER_INDEX_VERSION, sync.VERSION, {persist = true})
    device:set_field(REPORTED_USERS, {}, {persist = true})
    device:set_field(sync.USER_INDEX, MIN_USER_INDEX, {persist = true})
  end

  device:set_field(lock_utils.COMMAND_NAME, COMMAND_NAME, {persist = true})
  request_user(device, device:get_field(sync.USER_INDEX))
end

function sync.sync_after_delay(device)
  local delay_s = 15
  device.thread:call_with_delay(delay_s, function() sync_users_from_lock(device) end)
end

--- Handle a GetUserResponse received while syncing.
function sync.get_user_response_handler(device, ib)
  local expected_index = device:get_field(sync.USER_INDEX)
  if expected_index == nil then return end

  local elements = ib.info_block and ib.info_block.data and ib.info_block.data.elements
  if ib.status ~= im.InteractionResponse.Status.SUCCESS or elements == nil or elements.user_index == nil then
    handle_get_user_failure(device, expected_index, "error response")
    return
  end

  local user_index = elements.user_index.value
  if user_index < expected_index then
    device.log.warn_with({hub_logs = true}, string.format("Ignoring GetUserResponse for user index %s, already processed (expected %s)", user_index, expected_index))
    return
  elseif user_index > expected_index then
    -- the lock answered for a different user than the one asked for, so the expected one was not read
    handle_get_user_failure(device, expected_index, string.format("response was for user index %s", user_index))
    return
  end

  local user_status = elements.user_status and elements.user_status.value
  if user_status ~= nil and user_status ~= clusters.DoorLock.types.UserStatusEnum.AVAILABLE then
    local pins = {}
    for _, cred in ipairs(elements.credentials and elements.credentials.elements or {}) do
      local fields = cred.elements or {}
      if fields.credential_type and fields.credential_type.value == clusters.DoorLock.types.CredentialTypeEnum.PIN and
        fields.credential_index then
        table.insert(pins, fields.credential_index.value)
      end
    end
    local user_name = elements.user_name and elements.user_name.value
    local reported_users = utils.deep_copy(device:get_field(REPORTED_USERS) or {})
    table.insert(reported_users, {
      userIndex = user_index,
      userName = (user_name ~= nil and user_name ~= "") and user_name or nil,
      pins = pins,
    })
    device:set_field(REPORTED_USERS, reported_users, {persist = true})
  end

  local next_index = elements.next_user_index and elements.next_user_index.value
  if next_index == nil then -- per spec, nil when there is no next user
    finish_sync(device)
  elseif next_index <= user_index then -- should not happen
    device.log.warn_with({hub_logs = true}, string.format("Unexpected NextUserIndex %s for user index %s, reading the next index", next_index, user_index))
    advance_walk(device, user_index + 1)
  else
    advance_walk(device, next_index)
  end
end

return sync
