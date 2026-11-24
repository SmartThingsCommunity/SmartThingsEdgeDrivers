-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Tests for syncing the lockUsers/lockCredentials tables from the lock's Matter user database.
local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local cluster_base = require "st.matter.cluster_base"
local im = require "st.matter.interaction_model"
local DoorLock = clusters.DoorLock
local types = DoorLock.types
local lock_utils = require "lock_utils"
local lock_sync = require "lock_sync"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("lock-user-pin.yml"),
  manufacturer_info = {
    vendor_id = 0x135D,
    product_id = 0x00C1,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.BasicInformation.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 } -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = DoorLock.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0x0101, -- PIN & USR
        }
      },
      device_types = {
        { device_type_id = 0x000A, device_type_revision = 1 } -- Door Lock
      }
    }
  }
})

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

local function pin(index)
  return types.CredentialStruct({credential_type = types.CredentialTypeEnum.PIN, credential_index = index})
end

local function get_user_response(user_index, user_name, user_status, user_type, credentials, next_user_index, interaction_status)
  return DoorLock.client.commands.GetUserResponse:build_test_command_response(
    mock_device, 1,
    user_index,
    user_name,
    nil, -- user_uniqueid
    user_status,
    user_type,
    nil, -- credential_rule
    credentials,
    nil, -- creator_fabric_index
    nil, -- last_modified_fabric_index
    next_user_index,
    interaction_status
  )
end

local function expect_get_user(user_index)
  test.socket.matter:__expect_send({mock_device.id, DoorLock.server.commands.GetUser(mock_device, 1, user_index)})
end

-- Send a refresh, and advance past the delay before the refresh handler tries to sync.
local function refresh_and_wait_for_sync()
  test.timer.__create_and_queue_test_time_advance_timer(15, "oneshot")
  test.socket.capability:__queue_receive({mock_device.id, {capability = "refresh", component = "main", command = "refresh", args = {}}})
  test.socket.matter:__expect_send({mock_device.id, DoorLock.attributes.LockState:read(mock_device)})
  test.wait_for_events()
  test.mock_time.advance_time(15)
end

-- Send init, which subscribes and schedules a delayed sync.
local function init_device()
  local subscribe_request = DoorLock.attributes.LockState:subscribe(mock_device)
  subscribe_request:merge(DoorLock.attributes.OperatingMode:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.NumberOfTotalUsersSupported:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.NumberOfPINUsersSupported:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.MaxPINCodeLength:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.MinPINCodeLength:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.RequirePINforRemoteOperation:subscribe(mock_device))
  subscribe_request:merge(cluster_base.subscribe(mock_device, nil, DoorLock.ID, 0xFFFC))
  subscribe_request:merge(DoorLock.events.LockOperation:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.DoorLockAlarm:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.LockUserChange:subscribe(mock_device))

  test.timer.__create_and_queue_test_time_advance_timer(15, "oneshot")
  test.socket.device_lifecycle:__queue_receive({mock_device.id, "init"})
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.wait_for_events()
end

test.register_coroutine_test(
  "Init syncs users and credentials from the lock, following NextUserIndex",
  function()
    init_device()

    test.mock_time.advance_time(15)
    expect_get_user(1)
    test.wait_for_events()

    -- user 1 is occupied and owns two PINs; the next occupied user is 4 (users 2 and 3 are skipped)
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(
      1, "Alice", types.UserStatusEnum.OCCUPIED_ENABLED, types.UserTypeEnum.UNRESTRICTED_USER, {pin(1), pin(5)}, 4
    )})
    expect_get_user(4)
    test.wait_for_events()

    test.socket.matter:__queue_receive({mock_device.id, get_user_response(
      4, "", types.UserStatusEnum.OCCUPIED_DISABLED, types.UserTypeEnum.SCHEDULE_RESTRICTED_USER, {pin(2)}, nil
    )})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockUsers.users({
        {userIndex = 1, userName = "Guest 1", userType = "guest"},
        {userIndex = 4, userName = "Guest 4", userType = "guest"},
      }, {visibility = {displayed = false}})
    ))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.credentials({
        {userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1"},
        {userIndex = 1, credentialIndex = 5, credentialType = "pin", credentialName = "Guest 1"},
        {userIndex = 4, credentialIndex = 2, credentialType = "pin", credentialName = "Guest 4"},
      }, {visibility = {displayed = false}})
    ))
    test.wait_for_events()

    assert(mock_device:get_field(lock_sync.USERS_SYNCED) == lock_sync.VERSION, "sync should be marked complete")
    assert(mock_device:get_field(lock_sync.USER_INDEX) == nil, "sync index should be cleared")
    assert(mock_device:get_field(lock_utils.BUSY_STATE) == false, "busy state should be cleared")

    -- the sync only runs once: a later refresh does not send GetUser again
    refresh_and_wait_for_sync()
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

local function expect_tables(users, credentials)
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockUsers.users(users, {visibility = {displayed = false}})
  ))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockCredentials.credentials(credentials, {visibility = {displayed = false}})
  ))
end

test.register_coroutine_test(
  "Refresh syncs an empty lock",
  function()
    refresh_and_wait_for_sync()
    expect_get_user(1)
    test.wait_for_events()

    test.socket.matter:__queue_receive({mock_device.id, get_user_response(
      1, nil, types.UserStatusEnum.AVAILABLE, nil, nil, nil
    )})
    expect_tables({}, {})
    test.wait_for_events()
    assert(mock_device:get_field(lock_sync.USERS_SYNCED) == lock_sync.VERSION, "sync should be marked complete")
  end,
  { min_api_version = 15 }
)

local OCCUPIED = types.UserStatusEnum.OCCUPIED_ENABLED
local UNRESTRICTED = types.UserTypeEnum.UNRESTRICTED_USER

local function set_total_users_supported(count)
  test.socket.matter:__queue_receive({
    mock_device.id,
    DoorLock.attributes.NumberOfTotalUsersSupported:build_test_report_data(mock_device, 1, count)
  })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.lockUsers.totalUsersSupported(count, {visibility = {displayed = false}})
  ))
  test.wait_for_events()
end

local function fail_get_user()
  return get_user_response(1, nil, nil, nil, nil, nil, im.InteractionResponse.Status.FAILURE)
end

test.register_coroutine_test(
  "A user that fails is skipped and the sync moves on to the next index",
  function()
    set_total_users_supported(4)
    refresh_and_wait_for_sync()
    expect_get_user(1)
    test.wait_for_events()

    test.socket.matter:__queue_receive({mock_device.id, get_user_response(
      1, "Alice", OCCUPIED, UNRESTRICTED, {pin(1)}, 3
    )})
    expect_get_user(3)
    test.wait_for_events()

    test.socket.matter:__queue_receive({mock_device.id, get_user_response(
      3, nil, nil, nil, nil, nil, im.InteractionResponse.Status.FAILURE
    )})
    expect_get_user(4)
    test.wait_for_events()

    test.socket.matter:__queue_receive({mock_device.id, get_user_response(
      4, "Dan", OCCUPIED, UNRESTRICTED, {pin(2)}, nil
    )})
    expect_tables(
      {
        {userIndex = 1, userName = "Guest 1", userType = "guest"},
        {userIndex = 4, userName = "Guest 4", userType = "guest"},
      },
      {
        {userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1"},
        {userIndex = 4, credentialIndex = 2, credentialType = "pin", credentialName = "Guest 4"},
      }
    )
    test.wait_for_events()
    assert(mock_device:get_field(lock_sync.USERS_SYNCED) == lock_sync.VERSION, "sync should be marked complete")
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "Users that were already in the tables are kept when they cannot be read during a later sync",
  function()
    set_total_users_supported(4)
    refresh_and_wait_for_sync()
    expect_get_user(1)
    test.wait_for_events()
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(1, "Alice", OCCUPIED, UNRESTRICTED, {pin(1)}, 3)})
    expect_get_user(3)
    test.wait_for_events()
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(3, "Bob", OCCUPIED, UNRESTRICTED, {pin(2)}, nil)})
    expect_tables(
      {
        {userIndex = 1, userName = "Guest 1", userType = "guest"},
        {userIndex = 3, userName = "Guest 3", userType = "guest"},
      },
      {
        {userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1"},
        {userIndex = 3, credentialIndex = 2, credentialType = "pin", credentialName = "Guest 3"},
      }
    )
    test.wait_for_events()

    -- sync again, e.g. after a version bump; this time user 3 cannot be read
    mock_device:set_field(lock_sync.USERS_SYNCED, nil, {persist = true})
    refresh_and_wait_for_sync()
    expect_get_user(1)
    test.wait_for_events()
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(1, "Alice", OCCUPIED, UNRESTRICTED, {pin(1)}, 3)})
    expect_get_user(3)
    test.wait_for_events()
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(3, nil, nil, nil, nil, nil, im.InteractionResponse.Status.FAILURE)})
    expect_get_user(4)
    test.wait_for_events()
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(4, nil, types.UserStatusEnum.AVAILABLE, nil, nil, nil)})
    -- Bob is still in the tables
    expect_tables(
      {
        {userIndex = 1, userName = "Guest 1", userType = "guest"},
        {userIndex = 3, userName = "Guest 3", userType = "guest"},
      },
      {
        {userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1"},
        {userIndex = 3, credentialIndex = 2, credentialType = "pin", credentialName = "Guest 3"},
      }
    )
    test.wait_for_events()
    assert(mock_device:get_field(lock_sync.USERS_SYNCED) == lock_sync.VERSION, "sync should be marked complete")
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "Remote-only (COTA) users are not shown, whatever credential index they hold",
  function()
    -- the stored COTA index (1) is stale: the COTA actually lives at credential 12, owned by user 13
    mock_device:set_field(lock_utils.COTA_CRED_INDEX, 1, {persist = true})
    refresh_and_wait_for_sync()
    expect_get_user(1)
    test.wait_for_events()

    test.socket.matter:__queue_receive({mock_device.id, get_user_response(
      1, "Alice", types.UserStatusEnum.OCCUPIED_ENABLED, types.UserTypeEnum.UNRESTRICTED_USER, {pin(1)}, 13
    )})
    expect_get_user(13)
    test.wait_for_events()

    test.socket.matter:__queue_receive({mock_device.id, get_user_response(
      13, "", types.UserStatusEnum.OCCUPIED_ENABLED, types.UserTypeEnum.REMOTE_ONLY_USER, {pin(12)}, nil
    )})
    expect_tables(
      {{userIndex = 1, userName = "Guest 1", userType = "guest"}},
      {{userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1"}}
    )
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "Without the number of users supported, a user that fails ends the attempt and the next refresh resumes",
  function()
    refresh_and_wait_for_sync()
    expect_get_user(1)
    test.wait_for_events()

    test.socket.matter:__queue_receive({mock_device.id, fail_get_user()})
    expect_tables({}, {}) -- nothing has been read yet
    test.wait_for_events()
    assert(mock_device:get_field(lock_sync.USERS_SYNCED) == nil, "sync should not be marked complete")
    assert(mock_device:get_field(lock_sync.USER_INDEX) == 1, "sync index should be kept to resume from")
    assert(mock_device:get_field(lock_utils.BUSY_STATE) == false, "busy state should be cleared")

    refresh_and_wait_for_sync()
    expect_get_user(1)
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "A GetUserResponse for an already processed user index is ignored during a sync",
  function()
    refresh_and_wait_for_sync()
    expect_get_user(1)
    test.wait_for_events()
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(1, "Alice", OCCUPIED, UNRESTRICTED, {pin(1)}, 3)})
    expect_get_user(3)
    test.wait_for_events()

    -- a duplicate of the first response neither records a user again nor sends anything
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(1, "Alice", OCCUPIED, UNRESTRICTED, {pin(1)}, 3)})
    test.wait_for_events()
    assert(mock_device:get_field(lock_sync.USER_INDEX) == 3, "sync index should not change")

    test.socket.matter:__queue_receive({mock_device.id, get_user_response(3, "Bob", OCCUPIED, UNRESTRICTED, {pin(2)}, nil)})
    expect_tables(
      {
        {userIndex = 1, userName = "Guest 1", userType = "guest"},
        {userIndex = 3, userName = "Guest 3", userType = "guest"},
      },
      {
        {userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1"},
        {userIndex = 3, credentialIndex = 2, credentialType = "pin", credentialName = "Guest 3"},
      }
    )
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "A GetUserResponse for a later user index than requested counts as a failure and the user is skipped",
  function()
    set_total_users_supported(1)
    refresh_and_wait_for_sync()
    expect_get_user(1)
    test.wait_for_events()

    test.socket.matter:__queue_receive({mock_device.id, get_user_response(7, "Other", OCCUPIED, UNRESTRICTED, {pin(7)}, 8)})
    -- user 1 is skipped and, being the only user, ends the walk
    expect_tables({}, {})
    test.wait_for_events()
    assert(mock_device:get_field(lock_sync.USERS_SYNCED) == lock_sync.VERSION, "sync should be marked complete")
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "A migration names the users it reads from the legacy codes, and completes even if a user could not be read",
  function()
    set_total_users_supported(4)
    mock_device:set_field(lock_utils.LOCK_CODES_FOR_MIGRATION, { {"1", "Guest1"}, {"2", "Guest2"}, {"3", "Guest3"} }, {persist = true})

    refresh_and_wait_for_sync()
    expect_get_user(1)
    test.wait_for_events()
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(1, "x", OCCUPIED, UNRESTRICTED, {pin(1)}, 3)})
    expect_get_user(3)
    test.wait_for_events()
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(3, nil, nil, nil, nil, nil, im.InteractionResponse.Status.FAILURE)})
    expect_get_user(4)
    test.wait_for_events()
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(4, "y", OCCUPIED, UNRESTRICTED, {pin(2)}, nil)})
    expect_tables(
      {
        {userIndex = 1, userName = "Guest1", userType = "guest"},
        {userIndex = 4, userName = "Guest2", userType = "guest"},
      },
      {
        {userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest1"},
        {userIndex = 4, credentialIndex = 2, credentialType = "pin", credentialName = "Guest2"},
      }
    )
    test.wait_for_events()
    assert(mock_device:get_field(lock_sync.USERS_SYNCED) == lock_sync.VERSION, "sync should be complete")
    assert(mock_device:get_field(lock_utils.LOCK_CODES_FOR_MIGRATION) == nil, "legacy names should be cleared")
    assert(mock_device:get_field(lock_utils.BUSY_STATE) == false, "busy state should be cleared")
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "Without a response the attempt times out and applies what was read, and a late response continues the sync",
  function()
    refresh_and_wait_for_sync()
    -- the timeouts of the first two requests
    test.timer.__create_and_queue_test_time_advance_timer(10, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(10, "oneshot")
    expect_get_user(1)
    test.wait_for_events()
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(1, "Alice", OCCUPIED, UNRESTRICTED, {pin(1)}, 3)})
    expect_get_user(3)
    test.wait_for_events()

    -- user 3 does not answer in time
    test.mock_time.advance_time(10)
    expect_tables(
      {{userIndex = 1, userName = "Guest 1", userType = "guest"}},
      {{userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1"}}
    )
    test.wait_for_events()
    assert(mock_device:get_field(lock_sync.USERS_SYNCED) == nil, "sync should not be complete")
    assert(mock_device:get_field(lock_sync.USER_INDEX) == 3, "progress should be kept")
    assert(lock_sync.is_syncing(mock_device), "the sync should still be the command in progress")

    -- the late response is still handled by the sync, which completes
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(3, "Bob", OCCUPIED, UNRESTRICTED, {pin(2)}, nil)})
    expect_tables(
      {
        {userIndex = 1, userName = "Guest 1", userType = "guest"},
        {userIndex = 3, userName = "Guest 3", userType = "guest"},
      },
      {
        {userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1"},
        {userIndex = 3, credentialIndex = 2, credentialType = "pin", credentialName = "Guest 3"},
      }
    )
    test.wait_for_events()
    assert(mock_device:get_field(lock_sync.USERS_SYNCED) == lock_sync.VERSION, "sync should be complete")
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "The sync does not start while the device is busy with another command",
  function()
    init_device()
    -- another command is in flight when the delayed sync runs
    test.mock_time.advance_time(15)
    mock_device:set_field(lock_utils.BUSY_STATE, os.time(), {persist = true})
    test.wait_for_events()
    assert(mock_device:get_field(lock_sync.USER_INDEX) == nil, "sync should not have started")
  end,
  { min_api_version = 15 }
)

local REMOTE_ONLY = types.UserTypeEnum.REMOTE_ONLY_USER

-- Run a full sync. `lock_users` is what the lock holds, as a list of
-- {index = n, name = "...", type = <UserTypeEnum>, pins = {...}}, in index order.
local function sync_with_lock(lock_users, expected_users, expected_creds)
  refresh_and_wait_for_sync()
  for i, user in ipairs(lock_users) do
    expect_get_user(user.index)
    test.wait_for_events()
    local next_user = lock_users[i + 1]
    local pins = {}
    for _, p in ipairs(user.pins) do table.insert(pins, pin(p)) end
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(
      user.index, user.name or "", OCCUPIED, user.type or UNRESTRICTED, pins, next_user and next_user.index or nil)})
  end
  expect_tables(expected_users, expected_creds)
  test.wait_for_events()
end

-- Put the device in the state the old lockCodes migration left behind: one user per legacy slot, with
-- userIndex == credentialIndex == slot, and every user a "guest". USERS_SYNCED is cleared afterwards so the
-- next refresh syncs again.
local function store_tables_like_old_migration(codes)
  local lock_users, users, creds = {}, {}, {}
  for _, code in ipairs(codes) do
    local slot, name = code[1], code[2]
    table.insert(lock_users, {index = slot, name = name, pins = {slot}})
    table.insert(users, {userIndex = slot, userName = name, userType = "guest"})
    table.insert(creds, {userIndex = slot, credentialIndex = slot, credentialType = "pin", credentialName = name})
  end
  -- the lock's user names are not read, so the names come from the legacy codes, as in a real migration
  mock_device:set_field(lock_utils.LOCK_CODES_FOR_MIGRATION, codes, {persist = true})
  sync_with_lock(lock_users, users, creds)
  mock_device:set_field(lock_sync.USERS_SYNCED, nil, {persist = true})
end

test.register_coroutine_test(
  "The COTA user stored by the old migration is removed by the sync",
  function()
    set_total_users_supported(5)
    store_tables_like_old_migration({ {1, lock_utils.COTA_CODE_NAME}, {2, "Front Door"} })
    mock_device:set_field(lock_utils.COTA_CRED, "123456", {persist = true})
    mock_device:set_field(lock_utils.COTA_CRED_INDEX, 1, {persist = true})

    sync_with_lock(
      {
        {index = 1, type = REMOTE_ONLY, pins = {1}}, -- the driver's COTA user
        {index = 2, pins = {2}},
      },
      {{userIndex = 2, userName = "Front Door", userType = "guest"}},
      {{userIndex = 2, credentialIndex = 2, credentialType = "pin", credentialName = "Front Door"}}
    )
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "A user moved to its real lock index is not also left at its old index",
  function()
    set_total_users_supported(5)
    store_tables_like_old_migration({ {1, "Alice"}, {2, "Bob"} })

    sync_with_lock(
      {
        {index = 1, pins = {1}},
        {index = 3, pins = {2}},
      },
      {
        {userIndex = 1, userName = "Alice", userType = "guest"},
        {userIndex = 3, userName = "Bob", userType = "guest"},
      },
      {
        {userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Alice"},
        {userIndex = 3, credentialIndex = 2, credentialType = "pin", credentialName = "Bob"},
      }
    )
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "When the COTA PIN is moved to index 2, the sync hides the COTA user, not the real user at index 1",
  function()
    set_total_users_supported(5)

    -- the fields set_cota_credential(device, 1) sets just before it sends SetCredential at index 1
    mock_device:set_field(lock_utils.COTA_CRED, "654123", {persist = true})
    mock_device:set_field(lock_utils.COMMAND_NAME, "addCota")
    mock_device:set_field(lock_utils.CRED_INDEX, 1)
    mock_device:set_field(lock_utils.COTA_CRED_INDEX, 1, {persist = true})
    mock_device:set_field(lock_utils.USER_TYPE, "remote")

    -- the lock: index 1 is taken, try 2
    test.socket.matter:__queue_receive({mock_device.id,
      DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
        mock_device, 1, types.DlStatus.OCCUPIED, nil, 2)})
    test.socket.matter:__expect_send({mock_device.id, DoorLock.server.commands.SetCredential(
      mock_device, 1, types.DataOperationTypeEnum.ADD, pin(2), "654123", nil, nil, REMOTE_ONLY)})
    test.wait_for_events()

    -- the lock: COTA PIN stored at index 2, for a new user 2
    test.socket.matter:__queue_receive({mock_device.id,
      DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
        mock_device, 1, types.DlStatus.SUCCESS, 2, nil)})
    test.wait_for_events()

    sync_with_lock(
      {
        {index = 1, name = "Alice", pins = {1}},
        {index = 2, type = REMOTE_ONLY, pins = {2}}, -- the driver's COTA user
      },
      {{userIndex = 1, userName = "Guest 1", userType = "guest"}},
      {{userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1"}}
    )
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "A GetUser error status on the GetUser path makes the sync skip to the next user",
  function()
    set_total_users_supported(3)
    refresh_and_wait_for_sync()
    expect_get_user(1)
    test.wait_for_events()

    test.socket.matter:__queue_receive({mock_device.id, DoorLock:build_test_command_response(
      mock_device, 1, DoorLock.ID, DoorLock.server.commands.GetUser.ID, nil, im.InteractionResponse.Status.FAILURE)})
    expect_get_user(2)
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "addUser is rejected as busy while a sync is in progress, even after a refresh",
  function()
    set_total_users_supported(3)
    refresh_and_wait_for_sync()
    expect_get_user(1)
    test.wait_for_events()
    assert(lock_sync.is_syncing(mock_device), "precondition: sync in progress")

    test.socket.capability:__queue_receive({mock_device.id, {capability = "refresh", component = "main", command = "refresh", args = {}}})
    test.socket.matter:__expect_send({mock_device.id, DoorLock.attributes.LockState:read(mock_device)})
    test.wait_for_events()
    test.socket.capability:__queue_receive({mock_device.id,
      {capability = capabilities.lockUsers.ID, component = "main", command = "addUser", args = {"Carol", "guest"}}})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockUsers.commandResult({commandName = "addUser", statusCode = "busy"},
        {state_change = true, visibility = {displayed = false}})))
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "The SUCCESS status that accompanies a GetUserResponse does not advance the sync a second time",
  function()
    set_total_users_supported(3)
    refresh_and_wait_for_sync()
    expect_get_user(1)
    test.wait_for_events()

    test.socket.matter:__queue_receive({mock_device.id, DoorLock:build_test_command_response(
      mock_device, 1, DoorLock.ID, DoorLock.server.commands.GetUser.ID, nil, im.InteractionResponse.Status.SUCCESS)})
    test.wait_for_events() -- nothing is sent

    test.socket.matter:__queue_receive({mock_device.id, get_user_response(
      1, "Alice", types.UserStatusEnum.OCCUPIED_ENABLED, types.UserTypeEnum.UNRESTRICTED_USER, {pin(1)}, 2
    )})
    expect_get_user(2)
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "A GetUserResponse received when no addUser or sync is in progress does not send SetUser",
  function()
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(
      10, nil, types.UserStatusEnum.AVAILABLE, nil, nil, nil
    )})
    test.wait_for_events() -- nothing is sent or emitted
  end,
  { min_api_version = 15 }
)

-- The replies below are copied from an ULTRALOQ Smart Door Lock on a production hub (2026-11-24).
-- A successful GetUser returns two blocks in one message: the GetUserResponse, then a SUCCESS status on
-- the GetUser command path. User 1's name is not valid UTF-8, users 3 and 6 are NUL-padded to 10 bytes,
-- user 6 holds only a programming PIN, and user 6 reports no NextUserIndex.
local ULTRALOQ_USERS = {
  {index = 1, name = "\xC4\x0E\x02\x20\x00\x00\x00\x00\xA4\x0E", type = types.UserTypeEnum.UNRESTRICTED_USER, pin = 1, next = 2},
  {index = 2, name = "Heron Lo", type = types.UserTypeEnum.SCHEDULE_RESTRICTED_USER, pin = 2, next = 3},
  {index = 3, name = "Nathan Dw\x00", type = types.UserTypeEnum.SCHEDULE_RESTRICTED_USER, pin = 3, next = 4},
  {index = 4, name = "Melinda ", type = types.UserTypeEnum.SCHEDULE_RESTRICTED_USER, pin = 4, next = 5},
  {index = 5, name = "Luong", type = types.UserTypeEnum.SCHEDULE_RESTRICTED_USER, pin = 5, next = 6},
  {index = 6, name = "Madison M\x00", type = types.UserTypeEnum.SCHEDULE_RESTRICTED_USER, programming_pin = 0, next = nil},
}

-- A GetUserResponse followed by the SUCCESS status block for the GetUser command, in one message.
local function get_user_reply_as_sent_by_lock(user)
  local credentials
  if user.pin then
    credentials = {pin(user.pin)}
  else
    credentials = {types.CredentialStruct({
      credential_type = types.CredentialTypeEnum.PROGRAMMINGPIN, credential_index = user.programming_pin
    })}
  end
  local reply = get_user_response(user.index, user.name, OCCUPIED, user.type, credentials, user.next)
  local status_block = DoorLock:build_test_command_response(
    mock_device, 1, DoorLock.ID, DoorLock.server.commands.GetUser.ID, nil, im.InteractionResponse.Status.SUCCESS
  ).info_blocks[1]
  table.insert(reply.info_blocks, status_block)
  return reply
end

-- The datastore save JSON-encodes every persisted string, and the hub's encoder rejects invalid UTF-8.
local function assert_utf8_only(value, path)
  if type(value) == "string" then
    assert(utf8.len(value) ~= nil, string.format("persisted string at %s is not valid UTF-8", path))
  elseif type(value) == "table" then
    for k, v in pairs(value) do
      assert_utf8_only(k, path .. "[key]")
      assert_utf8_only(v, path .. "." .. tostring(k))
    end
  end
end

test.register_coroutine_test(
  "The ULTRALOQ's real GetUser replies sync every user and persist only valid UTF-8",
  function()
    set_total_users_supported(10)
    refresh_and_wait_for_sync()
    expect_get_user(1)
    test.wait_for_events()

    for _, user in ipairs(ULTRALOQ_USERS) do
      test.socket.matter:__queue_receive({mock_device.id, get_user_reply_as_sent_by_lock(user)})
      if user.next then
        -- exactly one GetUser for the next index: the SUCCESS status block must not skip ahead
        expect_get_user(user.next)
      else
        local users, creds = {}, {}
        for _, u in ipairs(ULTRALOQ_USERS) do
          table.insert(users, {userIndex = u.index, userName = "Guest " .. u.index, userType = "guest"})
          if u.pin then
            table.insert(creds, {userIndex = u.index, credentialIndex = u.pin, credentialType = "pin", credentialName = "Guest " .. u.index})
          end
        end
        expect_tables(users, creds)
      end
      test.wait_for_events()
      assert_utf8_only(mock_device:get_field("syncReportedUsers"), "syncReportedUsers")
    end
    assert(mock_device:get_field(lock_sync.USERS_SYNCED) == lock_sync.VERSION, "sync should be complete")
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "A late GetUserResponse for an empty index after the sync finishes does not add a user to the lock",
  function()
    -- left behind by an earlier command, as on the production hub
    mock_device:set_field(lock_utils.USER_NAME, "Melinda", {persist = true})
    set_total_users_supported(10)
    refresh_and_wait_for_sync()
    expect_get_user(1)
    test.wait_for_events()

    local only_user = {index = 1, name = nil, type = types.UserTypeEnum.UNRESTRICTED_USER, pin = 1, next = nil}
    test.socket.matter:__queue_receive({mock_device.id, get_user_reply_as_sent_by_lock(only_user)})
    expect_tables(
      {{userIndex = 1, userName = "Guest 1", userType = "guest"}},
      {{userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1"}}
    )
    test.wait_for_events()

    -- the lock's answer for an empty index carries only the user index; every other field is null
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(10, nil, nil, nil, nil, nil)})
    test.wait_for_events() -- no SetUser is sent and no commandResult is emitted
  end,
  { min_api_version = 15 }
)

-- A device paired with the "lock" profile, which has no lockUsers, as a newly paired lock has before
-- match_profile runs.
local new_lock = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("lock.yml"),
  manufacturer_info = { vendor_id = 0x135D, product_id = 0x00C2 },
  endpoints = mock_device.endpoints,
})

test.register_coroutine_test(
  "A sync is scheduled when a profile change adds lockUsers",
  function()
    test.mock_device.add_test_device(new_lock)

    -- init on the "lock" profile; the sync scheduled from init runs 15s later and does nothing
    local lock_only_subscribe = DoorLock.attributes.LockState:subscribe(new_lock)
    lock_only_subscribe:merge(DoorLock.attributes.OperatingMode:subscribe(new_lock))
    lock_only_subscribe:merge(cluster_base.subscribe(new_lock, nil, DoorLock.ID, 0xFFFC))
    lock_only_subscribe:merge(DoorLock.events.LockOperation:subscribe(new_lock))
    lock_only_subscribe:merge(DoorLock.events.DoorLockAlarm:subscribe(new_lock))
    test.timer.__create_and_queue_test_time_advance_timer(15, "oneshot")
    test.socket.device_lifecycle:__queue_receive({new_lock.id, "init"})
    test.socket.matter:__expect_send({new_lock.id, lock_only_subscribe})
    test.wait_for_events()
    test.mock_time.advance_time(15)
    test.wait_for_events()

    -- match_profile switches to a profile with lockUsers
    test.timer.__create_and_queue_test_time_advance_timer(15, "oneshot")
    test.socket.device_lifecycle:__queue_receive(new_lock:generate_info_changed({profile = t_utils.get_profile_definition("lock-user-pin.yml")}))
    local full_subscribe = DoorLock.attributes.LockState:subscribe(new_lock)
    full_subscribe:merge(DoorLock.attributes.OperatingMode:subscribe(new_lock))
    full_subscribe:merge(DoorLock.attributes.NumberOfTotalUsersSupported:subscribe(new_lock))
    full_subscribe:merge(DoorLock.attributes.NumberOfPINUsersSupported:subscribe(new_lock))
    full_subscribe:merge(DoorLock.attributes.MaxPINCodeLength:subscribe(new_lock))
    full_subscribe:merge(DoorLock.attributes.MinPINCodeLength:subscribe(new_lock))
    full_subscribe:merge(DoorLock.attributes.RequirePINforRemoteOperation:subscribe(new_lock))
    full_subscribe:merge(cluster_base.subscribe(new_lock, nil, DoorLock.ID, 0xFFFC))
    full_subscribe:merge(DoorLock.events.LockOperation:subscribe(new_lock))
    full_subscribe:merge(DoorLock.events.DoorLockAlarm:subscribe(new_lock))
    full_subscribe:merge(DoorLock.events.LockUserChange:subscribe(new_lock))
    test.socket.matter:__expect_send({new_lock.id, full_subscribe})
    test.socket.capability:__expect_send(new_lock:generate_test_message("main", capabilities.lockAlarm.alarm.clear({state_change = true})))
    test.socket.capability:__expect_send(new_lock:generate_test_message("main",
      capabilities.lockAlarm.supportedAlarmValues({"unableToLockTheDoor"}, {visibility = {displayed = false}})))
    test.wait_for_events()

    -- a sync should now start
    test.mock_time.advance_time(15)
    test.socket.matter:__expect_send({new_lock.id, DoorLock.server.commands.GetUser(new_lock, 1, 1)})
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

test.run_registered_tests()
