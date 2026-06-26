-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local DoorLock = clusters.DoorLock
local cluster_base = require "st.matter.cluster_base"
local lock_utils = require "lock_utils"

local enabled_optional_component_capability_pairs = {{
    "main",
    {
      capabilities.lockUsers.ID,
      capabilities.lockCredentials.ID,
      capabilities.lockSchedules.ID
    }
  }}

local profiling_data = {
    BATTERY_SUPPORT = "__BATTERY_SUPPORT",
}

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition(
    "lock-modular.yml",
    {enabled_optional_capabilities = enabled_optional_component_capability_pairs}
  ),
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
          feature_map = 0x0591, -- PIN & WDSCH & USR & COTA & YDSCH
        }
      },
      device_types = {
        { device_type_id = 0x000A, device_type_revision = 1 } -- Door Lock
      }
    }
  }
})

local DoorLockFeatureMapAttr = {ID = 0xFFFC, cluster = DoorLock.ID}
local subscribe_request = DoorLock.attributes.LockState:subscribe(mock_device)
subscribe_request:merge(DoorLock.attributes.OperatingMode:subscribe(mock_device))
subscribe_request:merge(DoorLock.attributes.NumberOfTotalUsersSupported:subscribe(mock_device))
subscribe_request:merge(DoorLock.attributes.NumberOfPINUsersSupported:subscribe(mock_device))
subscribe_request:merge(DoorLock.attributes.MaxPINCodeLength:subscribe(mock_device))
subscribe_request:merge(DoorLock.attributes.MinPINCodeLength:subscribe(mock_device))
subscribe_request:merge(DoorLock.attributes.RequirePINforRemoteOperation:subscribe(mock_device))
subscribe_request:merge(DoorLock.attributes.NumberOfWeekDaySchedulesSupportedPerUser:subscribe(mock_device))
subscribe_request:merge(DoorLock.attributes.NumberOfYearDaySchedulesSupportedPerUser:subscribe(mock_device))
subscribe_request:merge(cluster_base.subscribe(mock_device, nil, DoorLockFeatureMapAttr.cluster, DoorLockFeatureMapAttr.ID))
subscribe_request:merge(DoorLock.events.LockOperation:subscribe(mock_device))
subscribe_request:merge(DoorLock.events.DoorLockAlarm:subscribe(mock_device))
subscribe_request:merge(DoorLock.events.LockUserChange:subscribe(mock_device))

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lockAlarm.alarm.clear({state_change = true}))
  )
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lock.supportedLockValues({"locked", "unlocked", "not fully locked"}, {visibility = {displayed = false}}))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
  )
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Migration completed and User and Credential values restored",
  function()
    mock_device:set_field(lock_utils.LOCK_CODES_COPY_REQUIRED, true, {persist = true})
    mock_device:set_field(profiling_data.BATTERY_SUPPORT, nil, {persist=true})
    mock_device:set_field(lock_utils.LOCK_CODES_FOR_MIGRATION, { {1, "ST Remote Operation Code"}, {2, "Guest1"}, {3, "Guest2"} }, {persist=true})
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = capabilities.refresh.ID, command = "refresh", args = {}}
      }
    )
    test.socket.matter:__expect_send({
      mock_device.id,
      clusters.PowerSource.attributes.AttributeList:read(mock_device)
    })
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ profile = t_utils.get_profile_definition("lock.yml")}))
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
