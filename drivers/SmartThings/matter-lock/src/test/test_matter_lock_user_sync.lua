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
        {userIndex = 1, userName = "Alice", userType = "guest"},
        {userIndex = 4, userName = "Guest 4", userType = "guest"},
      }, {visibility = {displayed = false}})
    ))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCredentials.credentials({
        {userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Alice"},
        {userIndex = 1, credentialIndex = 5, credentialType = "pin", credentialName = "Alice"},
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
        {userIndex = 1, userName = "Alice", userType = "guest"},
        {userIndex = 4, userName = "Dan", userType = "guest"},
      },
      {
        {userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Alice"},
        {userIndex = 4, credentialIndex = 2, credentialType = "pin", credentialName = "Dan"},
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
        {userIndex = 1, userName = "Alice", userType = "guest"},
        {userIndex = 3, userName = "Bob", userType = "guest"},
      },
      {
        {userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Alice"},
        {userIndex = 3, credentialIndex = 2, credentialType = "pin", credentialName = "Bob"},
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
        {userIndex = 1, userName = "Alice", userType = "guest"},
        {userIndex = 3, userName = "Bob", userType = "guest"},
      },
      {
        {userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Alice"},
        {userIndex = 3, credentialIndex = 2, credentialType = "pin", credentialName = "Bob"},
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
      {{userIndex = 1, userName = "Alice", userType = "guest"}},
      {{userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Alice"}}
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
        {userIndex = 1, userName = "Alice", userType = "guest"},
        {userIndex = 3, userName = "Bob", userType = "guest"},
      },
      {
        {userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Alice"},
        {userIndex = 3, credentialIndex = 2, credentialType = "pin", credentialName = "Bob"},
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
      {{userIndex = 1, userName = "Alice", userType = "guest"}},
      {{userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Alice"}}
    )
    test.wait_for_events()
    assert(mock_device:get_field(lock_sync.USERS_SYNCED) == nil, "sync should not be complete")
    assert(mock_device:get_field(lock_sync.USER_INDEX) == 3, "progress should be kept")
    assert(lock_sync.is_syncing(mock_device), "the sync should still be the command in progress")

    -- the late response is still handled by the sync, which completes
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(3, "Bob", OCCUPIED, UNRESTRICTED, {pin(2)}, nil)})
    expect_tables(
      {
        {userIndex = 1, userName = "Alice", userType = "guest"},
        {userIndex = 3, userName = "Bob", userType = "guest"},
      },
      {
        {userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Alice"},
        {userIndex = 3, credentialIndex = 2, credentialType = "pin", credentialName = "Bob"},
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

test.run_registered_tests()
