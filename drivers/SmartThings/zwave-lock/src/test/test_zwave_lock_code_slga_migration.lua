-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
--- @type st.zwave.CommandClass.UserCode
local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 2 })
local t_utils = require "integration_test.utils"
--- @type st.zwave.constants
local constants = require "st.zwave.constants"

local SCHLAGE_MANUFACTURER_ID = 0x003B
local SCHLAGE_PRODUCT_TYPE = 0x0002
local SCHLAGE_PRODUCT_ID = 0x0469

local zwave_lock_endpoints = {
  {
    command_classes = {
      { value = zw.BATTERY },
      { value = zw.DOOR_LOCK },
      { value = zw.USER_CODE },
      { value = zw.NOTIFICATION }
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("base-lock-tamper.yml"),
    zwave_endpoints = zwave_lock_endpoints,
    useOldCapabilityForTesting = true,
  }
)

local schlage_mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("base-lock.yml"),
    zwave_endpoints = zwave_lock_endpoints,
    zwave_manufacturer_id = SCHLAGE_MANUFACTURER_ID,
    zwave_product_type = SCHLAGE_PRODUCT_TYPE,
    zwave_product_id = SCHLAGE_PRODUCT_ID,
    useOldCapabilityForTesting = true,
  }
)

local SCHLAGE_LOCK_CODE_LENGTH_PARAM = {number = 16, size = 1}

local function init_code_slot(slot_number, name, device)
  local lock_codes = device.persistent_store[constants.LOCK_CODES]
  if lock_codes == nil then
    lock_codes = {}
    device.persistent_store[constants.LOCK_CODES] = lock_codes
  end
  lock_codes[tostring(slot_number)] = name
end

local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(schlage_mock_device)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Device called 'migrate' command",
    function()
      init_code_slot(1, "Zach", mock_device)
      init_code_slot(5, "Steven", mock_device)
      -- setup codes
      test.socket.zwave:__queue_receive({mock_device.id, UserCode:UsersNumberReport({ supported_users = 4 })   })
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.maxCodes(4,  { visibility = { displayed = false } })))
      test.wait_for_events()
      -- Validate migrate command
      test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "migrate", args = {} } })
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.minPinCodeLen(4,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.maxPinCodeLen(10,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.pinUsersSupported(4,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.credentials({{credentialIndex=1, credentialType="pin", userIndex=1}, {credentialIndex=5, credentialType="pin", userIndex=2}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.supportedCredentials({"pin"},  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockUsers.totalUsersSupported(4, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockUsers.users({{userIndex=1, userName="Zach", userType="guest"}, {userIndex=2, userName="Steven", userType="guest"}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true,  { visibility = { displayed = false } })))
    end
)

test.register_coroutine_test(
  "Migrate new device",
  function()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "migrate", args = {} } })
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.minPinCodeLen(4,  { visibility = { displayed = false } })))
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.maxPinCodeLen(10,  { visibility = { displayed = false } })))
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.pinUsersSupported(8,  { visibility = { displayed = false } })))
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.credentials({}, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.supportedCredentials({"pin"},  { visibility = { displayed = false } })))
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockUsers.totalUsersSupported(8, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockUsers.users({}, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true,  { visibility = { displayed = false } })))
  end
)

test.register_coroutine_test(
    "Schlage-Lock device called 'migrate' command, validate codeLength is being properly set",
    function()
      init_code_slot(1, "Zach", schlage_mock_device)
      init_code_slot(5, "Steven", schlage_mock_device)
      -- setup codes
      test.socket.zwave:__queue_receive({schlage_mock_device.id, UserCode:UsersNumberReport({ supported_users = 4 })   })
      test.socket.zwave:__queue_receive({schlage_mock_device.id, Configuration:Report({ parameter_number = SCHLAGE_LOCK_CODE_LENGTH_PARAM.number, configuration_value = 6 })})
      test.socket.capability:__expect_send( schlage_mock_device:generate_test_message("main", capabilities.lockCodes.maxCodes(4,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( schlage_mock_device:generate_test_message("main", capabilities.lockCodes.codeLength(6)))
      test.wait_for_events()
      -- Validate migrate command
      test.socket.capability:__queue_receive({ schlage_mock_device.id, { capability = capabilities.lockCodes.ID, command = "migrate", args = {} } })
      test.socket.capability:__expect_send( schlage_mock_device:generate_test_message("main", capabilities.lockCredentials.minPinCodeLen(6,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( schlage_mock_device:generate_test_message("main", capabilities.lockCredentials.maxPinCodeLen(6,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( schlage_mock_device:generate_test_message("main", capabilities.lockCredentials.pinUsersSupported(4,  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( schlage_mock_device:generate_test_message("main", capabilities.lockCredentials.credentials({{credentialIndex=1, credentialType="pin", userIndex=1}, {credentialIndex=5, credentialType="pin", userIndex=2}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( schlage_mock_device:generate_test_message("main", capabilities.lockCredentials.supportedCredentials({"pin"},  { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( schlage_mock_device:generate_test_message("main", capabilities.lockUsers.totalUsersSupported(4, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( schlage_mock_device:generate_test_message("main", capabilities.lockUsers.users({{userIndex=1, userName="Zach", userType="guest"}, {userIndex=2, userName="Steven", userType="guest"}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( schlage_mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true,  { visibility = { displayed = false } })))
    end
)

test.run_registered_tests()