-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local clusters = require "st.zigbee.zcl.clusters"
local DoorLock = clusters.DoorLock
local PowerConfiguration = clusters.PowerConfiguration
local Alarm = clusters.Alarms
local capabilities = require "st.capabilities"
local constants = require "lock_utils.constants"

local json = require "st.json"

local mock_datastore = require "integration_test.mock_env_datastore"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("base-lock.yml"),
      data = {
        lockCodes = json.encode({
          ["1"] = "Zach",
          ["5"] = "Steven"
        }),
      }
    }
)

local zero_slot_mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("base-lock.yml"),
      data = {
        lockCodes = json.encode({
          ["0"] = "Zero",
          ["1"] = "Zach"
        }),
      }
    }
)

local yale_zero_slot_mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("base-lock.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Yale",
          model = "YRD256",
          server_clusters = { DoorLock.ID },
        },
      },
      data = {
        lockCodes = json.encode({
          ["0"] = "Master Code",
          ["1"] = "Zach"
        }),
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(zero_slot_mock_device)
  test.mock_device.add_test_device(yale_zero_slot_mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Device called 'migrate' command",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device.id, "lockCodes", { ["1"] = "Zach", ["5"] = "Steven" })
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device.id, "migrationComplete", true)
      -- Set min/max code length attributes
      test.socket.zigbee:__queue_receive({ mock_device.id, DoorLock.attributes.MinPINCodeLength:build_test_attr_report(mock_device, 5) })
      test.socket.zigbee:__queue_receive({ mock_device.id, DoorLock.attributes.MaxPINCodeLength:build_test_attr_report(mock_device, 10) })
      test.socket.zigbee:__queue_receive({ mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:build_test_attr_report(mock_device, 4) })
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(5,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(10,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.maxCodes(4,  { visibility = { displayed = false } })))
      test.wait_for_events()
      -- Validate `migrate` command functionality.
      test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "migrate", args = {} } })

      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.supportedCredentials({"pin"},  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.minPinCodeLen(5,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.maxPinCodeLen(10,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.pinUsersSupported(5,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockUsers.totalUsersSupported(5, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockUsers.users({{userIndex=1, userName="Zach", userType="guest"}, {userIndex=5, userName="Steven", userType="guest"}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.credentials({{credentialIndex=1, credentialType="pin", userIndex=1, credentialName="Zach"}, {credentialIndex=5, credentialType="pin", userIndex=5, credentialName="Steven"}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true,  { visibility = { displayed = false } })))
      test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, Alarm.attributes.AlarmCount:read(mock_device) })
      test.wait_for_events()
      assert(mock_device:get_field(constants.DRIVER_STATE.SLGA_MIGRATED) == true, "SLGA_MIGRATED field should be set to true after migration")
    end
)

test.register_coroutine_test(
    "Migrate keeps slot 0 as a credential with a valid, non-conflicting userIndex",
    function()
      test.socket.device_lifecycle:__queue_receive({ zero_slot_mock_device.id, "init" })
      test.socket.zigbee:__queue_receive({ zero_slot_mock_device.id, DoorLock.attributes.MinPINCodeLength:build_test_attr_report(zero_slot_mock_device, 5) })
      test.socket.zigbee:__queue_receive({ zero_slot_mock_device.id, DoorLock.attributes.MaxPINCodeLength:build_test_attr_report(zero_slot_mock_device, 10) })
      test.socket.zigbee:__queue_receive({ zero_slot_mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:build_test_attr_report(zero_slot_mock_device, 4) })
      test.socket.capability:__expect_send( zero_slot_mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(5,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( zero_slot_mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(10,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( zero_slot_mock_device:generate_test_message("main", capabilities.lockCodes.maxCodes(4,  { visibility = { displayed = false } })))
      test.wait_for_events()
      test.socket.capability:__queue_receive({ zero_slot_mock_device.id, { capability = capabilities.lockCodes.ID, command = "migrate", args = {} } })
      -- slot 0 is a valid credentialIndex but not a valid userIndex (minimum 1), so its user gets the next free userIndex, 2, without displacing slot 1.
      test.socket.capability:__expect_send( zero_slot_mock_device:generate_test_message("main", capabilities.lockCredentials.supportedCredentials({"pin"},  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( zero_slot_mock_device:generate_test_message("main", capabilities.lockCredentials.minPinCodeLen(5,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( zero_slot_mock_device:generate_test_message("main", capabilities.lockCredentials.maxPinCodeLen(10,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( zero_slot_mock_device:generate_test_message("main", capabilities.lockCredentials.pinUsersSupported(5,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( zero_slot_mock_device:generate_test_message("main", capabilities.lockUsers.totalUsersSupported(5, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( zero_slot_mock_device:generate_test_message("main", capabilities.lockUsers.users({{userIndex=2, userName="Zero", userType="guest"}, {userIndex=1, userName="Zach", userType="guest"}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( zero_slot_mock_device:generate_test_message("main", capabilities.lockCredentials.credentials({{credentialIndex=0, credentialType="pin", userIndex=2, credentialName="Zero"}, {credentialIndex=1, credentialType="pin", userIndex=1, credentialName="Zach"}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( zero_slot_mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true,  { visibility = { displayed = false } })))
      test.socket.zigbee:__expect_send({ zero_slot_mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(zero_slot_mock_device) })
      test.socket.zigbee:__expect_send({ zero_slot_mock_device.id, DoorLock.attributes.LockState:read(zero_slot_mock_device) })
      test.socket.zigbee:__expect_send({ zero_slot_mock_device.id, Alarm.attributes.AlarmCount:read(zero_slot_mock_device) })
      test.wait_for_events()
    end
)

test.register_coroutine_test(
    "Yale migrate treats slot 0 as a master code user",
    function()
      test.socket.device_lifecycle:__queue_receive({ yale_zero_slot_mock_device.id, "init" })
      test.socket.zigbee:__queue_receive({ yale_zero_slot_mock_device.id, DoorLock.attributes.MinPINCodeLength:build_test_attr_report(yale_zero_slot_mock_device, 5) })
      test.socket.zigbee:__queue_receive({ yale_zero_slot_mock_device.id, DoorLock.attributes.MaxPINCodeLength:build_test_attr_report(yale_zero_slot_mock_device, 10) })
      test.socket.zigbee:__queue_receive({ yale_zero_slot_mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:build_test_attr_report(yale_zero_slot_mock_device, 4) })
      test.socket.capability:__expect_send( yale_zero_slot_mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(5,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( yale_zero_slot_mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(10,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( yale_zero_slot_mock_device:generate_test_message("main", capabilities.lockCodes.maxCodes(4,  { visibility = { displayed = false } })))
      test.wait_for_events()
      test.socket.capability:__queue_receive({ yale_zero_slot_mock_device.id, { capability = capabilities.lockCodes.ID, command = "migrate", args = {} } })
      -- slot 0 is a valid credentialIndex but not a valid userIndex (minimum 1). It must not displace slot 1's valid
      -- userIndex, so slot 0's user gets the next free value, 2.
      test.socket.capability:__expect_send( yale_zero_slot_mock_device:generate_test_message("main", capabilities.lockCredentials.supportedCredentials({"pin"},  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( yale_zero_slot_mock_device:generate_test_message("main", capabilities.lockCredentials.minPinCodeLen(5,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( yale_zero_slot_mock_device:generate_test_message("main", capabilities.lockCredentials.maxPinCodeLen(10,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( yale_zero_slot_mock_device:generate_test_message("main", capabilities.lockCredentials.pinUsersSupported(5,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( yale_zero_slot_mock_device:generate_test_message("main", capabilities.lockUsers.totalUsersSupported(5, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( yale_zero_slot_mock_device:generate_test_message("main", capabilities.lockUsers.users({{userIndex=2, userName="Master Code", userType="controlOnlyMember"}, {userIndex=1, userName="Zach", userType="guest"}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( yale_zero_slot_mock_device:generate_test_message("main", capabilities.lockCredentials.credentials({{credentialIndex=0, credentialType="pin", userIndex=2, credentialName="Master Code"}, {credentialIndex=1, credentialType="pin", userIndex=1, credentialName="Zach"}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( yale_zero_slot_mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true,  { visibility = { displayed = false } })))
      test.socket.zigbee:__expect_send({ yale_zero_slot_mock_device.id, DoorLock.attributes.LockState:read(yale_zero_slot_mock_device) })
      test.socket.zigbee:__expect_send({ yale_zero_slot_mock_device.id, Alarm.attributes.AlarmCount:read(yale_zero_slot_mock_device) })
      test.wait_for_events()
    end
)

test.run_registered_tests()
