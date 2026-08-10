-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local DoorLock = clusters.DoorLock
local lock_utils = require "lock_utils"

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
  -- mock_device:set_field(lock_utils.LOCK_CODES_FOR_MIGRATION, { {1, "ST Remote Operation Code"}, {2, "Guest1"}, {3, "Guest2"} }, {persist=true})
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

test.register_coroutine_test(
  "Migration completed and User and Credential values restored",
  function()
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
    -- assume this was set prior
    mock_device:set_field(lock_utils.LOCK_CODES_FOR_MIGRATION, { {1, "ST Remote Operation Code"}, {2, "Guest1"}, {3, "Guest2"} }, {persist=true})
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
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {
            {userIndex=1, userName="ST Remote Operation Code", userType="guest"},
            {userIndex=2, userName="Guest1", userType="guest"},
            {userIndex=3, userName="Guest2", userType="guest"}
          },
          {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials(
          {
            {credentialIndex=1, credentialType="pin", userIndex=1},
            {credentialIndex=2, credentialType="pin", userIndex=2},
            {credentialIndex=3, credentialType="pin", userIndex=3}
          },
          {visibility={displayed=false}}
        )
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.run_registered_tests()
