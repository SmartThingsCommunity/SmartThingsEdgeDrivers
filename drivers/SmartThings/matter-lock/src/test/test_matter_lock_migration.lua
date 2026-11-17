-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local DoorLock = clusters.DoorLock
local lock_utils = require "lock_utils"
local lock_sync = require "lock_sync"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("base-lock.yml"),
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

local subscribe_request = DoorLock.attributes.LockState:subscribe(mock_device)
subscribe_request:merge(DoorLock.attributes.OperatingMode:subscribe(mock_device))
subscribe_request:merge(DoorLock.attributes.NumberOfTotalUsersSupported:subscribe(mock_device))
subscribe_request:merge(DoorLock.attributes.NumberOfPINUsersSupported:subscribe(mock_device))
subscribe_request:merge(DoorLock.attributes.MaxPINCodeLength:subscribe(mock_device))
subscribe_request:merge(DoorLock.attributes.MinPINCodeLength:subscribe(mock_device))
subscribe_request:merge(DoorLock.attributes.RequirePINforRemoteOperation:subscribe(mock_device))
subscribe_request:merge(DoorLock.events.LockOperation:subscribe(mock_device))
subscribe_request:merge(DoorLock.events.DoorLockAlarm:subscribe(mock_device))
subscribe_request:merge(DoorLock.events.LockUserChange:subscribe(mock_device))

local enabled_optional_component_capability_pairs = {{
  "main",
  {
    capabilities.lockUsers.ID,
    capabilities.lockCredentials.ID,
    capabilities.battery.ID,
  }
}}

-- Run the migrate command through to the profile change, with the lockCodes stored by the unmigrated driver.
-- lockCodes are keyed by PIN credential index; slot 1 is the COTA credential.
local function migrate()
  test.wait_for_events()
  test.socket.capability:__queue_receive(
    {
      mock_device.id,
      {capability = capabilities.lockCodes.ID, command = "migrate", args = {}}
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true))
  )
  -- at this point, refresh is injected in migration.
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lock.supportedLockValues({"locked", "unlocked", "not fully locked"}, {visibility = {displayed = false}}))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
  )
  mock_device:expect_metadata_update({ profile = "lock-modular", optional_component_capabilities = enabled_optional_component_capability_pairs })
  test.wait_for_events()

  -- assume these were set prior by the unmigrated driver
  mock_device:set_field(lock_utils.LOCK_CODES_FOR_MIGRATION, { {"1", "ST Remote Operation Code"}, {"2", "Guest1"}, {"3", "Guest2"} }, {persist=true})
  mock_device:set_field(lock_utils.COTA_CRED, "123456", {persist = true})
  mock_device:set_field(lock_utils.COTA_CRED_INDEX, 1, {persist = true})

  test.timer.__create_and_queue_test_time_advance_timer(15, "oneshot")
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(
    {profile = {id = "00000000-1111-2222-3333-000000000010", components = { main = {capabilities={
      ["lock"]= {id="lock", version=1}, ["lockAlarm"] = {id="lockAlarm", version=1}, ["remoteControlStatus"] = {id="remoteControlStatus", version=1},
      ["lockUsers"] = {id="lockUsers", version=1}, ["lockCredentials"] = {id="lockCredentials", version=1}, ["firmwareUpdate"] = {id="firmwareUpdate", version=1},
      ["refresh"] = {id="refresh", version=1}}}}}}
  ))
  test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lockAlarm.alarm.clear({state_change = true}))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lockAlarm.supportedAlarmValues({"unableToLockTheDoor"}, {visibility = {displayed = false}}))
  )
  -- the lock's user index for each code is unknown until the sync, so no tables are emitted yet
  test.wait_for_events()
end

local function pin(index)
  return DoorLock.types.CredentialStruct({credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = index})
end

local function get_user_response(user_index, user_type, credentials, next_user_index)
  return DoorLock.client.commands.GetUserResponse:build_test_command_response(
    mock_device, 1, user_index, nil, nil, DoorLock.types.UserStatusEnum.OCCUPIED_ENABLED, user_type, nil,
    credentials, nil, nil, next_user_index
  )
end

test.register_coroutine_test(
  "Migration does not emit users or credentials before the sync, and starts a sync",
  function()
    migrate()
    test.mock_time.advance_time(15)
    test.socket.matter:__expect_send({mock_device.id, DoorLock.server.commands.GetUser(mock_device, 1, 1)})
    test.wait_for_events()
    assert(mock_device:get_field(lock_utils.LOCK_CODES_COPY_REQUIRED) == false, "migration should be marked handled")
  end,
  {
     min_api_version = 15
  }
)

test.register_coroutine_test(
  "The sync after migration builds the tables with legacy names at the lock's user indices",
  function()
    migrate()
    test.mock_time.advance_time(15)
    test.socket.matter:__expect_send({mock_device.id, DoorLock.server.commands.GetUser(mock_device, 1, 1)})
    test.wait_for_events()

    -- On the lock: user 1 is the COTA user (PIN 1), Guest2's PIN 3 was added first so it belongs to
    -- user 2, and Guest1's PIN 2 belongs to user 3.
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(1, DoorLock.types.UserTypeEnum.REMOTE_ONLY_USER, {pin(1)}, 2)})
    test.socket.matter:__expect_send({mock_device.id, DoorLock.server.commands.GetUser(mock_device, 1, 2)})
    test.wait_for_events()
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(2, DoorLock.types.UserTypeEnum.UNRESTRICTED_USER, {pin(3)}, 3)})
    test.socket.matter:__expect_send({mock_device.id, DoorLock.server.commands.GetUser(mock_device, 1, 3)})
    test.wait_for_events()
    test.socket.matter:__queue_receive({mock_device.id, get_user_response(3, DoorLock.types.UserTypeEnum.UNRESTRICTED_USER, {pin(2)}, nil)})

    -- names follow their credentials to the lock's user indices, and the COTA user is not shown
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {
            {userIndex=2, userName="Guest2", userType="guest"},
            {userIndex=3, userName="Guest1", userType="guest"}
          },
          {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials(
          {
            {credentialIndex=3, credentialType="pin", userIndex=2, credentialName="Guest2"},
            {credentialIndex=2, credentialType="pin", userIndex=3, credentialName="Guest1"}
          },
          {visibility={displayed=false}}
        )
      )
    )
    test.wait_for_events()
    assert(mock_device:get_field(lock_sync.USERS_SYNCED) == lock_sync.VERSION, "sync should be marked complete")
    assert(mock_device:get_field(lock_utils.LOCK_CODES_FOR_MIGRATION) == nil, "legacy codes should be cleared once synced")
  end,
  {
     min_api_version = 15
  }
)

test.run_registered_tests()
