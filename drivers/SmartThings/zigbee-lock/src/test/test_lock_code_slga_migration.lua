-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local clusters = require "st.zigbee.zcl.clusters"
local DoorLock = clusters.DoorLock
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

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
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
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.pinUsersSupported(4,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockUsers.totalUsersSupported(4, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockUsers.users({{userIndex=1, userName="Zach", userType="guest"}, {userIndex=5, userName="Steven", userType="guest"}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.credentials({{credentialIndex=1, credentialType="pin", userIndex=1, credentialName="Zach"}, {credentialIndex=5, credentialType="pin", userIndex=5, credentialName="Steven"}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true,  { visibility = { displayed = false } })))
      test.wait_for_events()
      assert(mock_device:get_field(constants.DRIVER_STATE.SLGA_MIGRATED) == true, "SLGA_MIGRATED field should be set to true after migration")
    end
)

test.run_registered_tests()