-- Copyright 2025 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

-- Mock out globals
local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
--- @type st.zwave.CommandClass.DoorLock
local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.UserCode
local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 2 })
local t_utils = require "integration_test.utils"
local zw_test_utils = require "integration_test.zwave_test_utils"
local utils = require "st.utils"
local mock_datastore = require "integration_test.mock_env_datastore"
local json = require "dkjson"

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

local lockCodes = {
  ["1"] = "Zach",
  ["5"] = "Steven"
}

local mock_device = test.mock_device.build_test_zwave_device(
    {
      profile = t_utils.get_profile_definition("base-lock-tamper.yml"),
      zwave_endpoints = zwave_lock_endpoints,
      data = {
        lockCodes = json.encode(utils.deep_copy(lockCodes))
      }
    }
)

local schlage_mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("base-lock.yml"),
    zwave_endpoints = zwave_lock_endpoints,
    zwave_manufacturer_id = SCHLAGE_MANUFACTURER_ID,
    zwave_product_type = SCHLAGE_PRODUCT_TYPE,
    zwave_product_id = SCHLAGE_PRODUCT_ID,
    data = {
      lockCodes = json.encode(utils.deep_copy(lockCodes))
    }
  }
)

local SCHLAGE_LOCK_CODE_LENGTH_PARAM = {number = 16, size = 1}

test.register_coroutine_test(
    "Device called 'migrate' command",
    function()
      test.mock_device.add_test_device(mock_device)
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              DoorLock:OperationGet({})
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Battery:Get({})
          )
      )
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device.id, "_lock_codes", { ["1"] = "Zach", ["5"] = "Steven" })
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device.id, "migrationComplete", true)
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
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockUsers.users({{userIndex=1, userName="Zach", userType="guest"}, {userIndex=2, userName="Steven", userType="guest"}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true,  { visibility = { displayed = false } })))
    end
)

test.register_coroutine_test(
    "Schlage-Lock device called 'migrate' command, validate codeLength is being properly set",
    function()
      test.mock_device.add_test_device(schlage_mock_device)
      test.socket.device_lifecycle:__queue_receive({ schlage_mock_device.id, "added" })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              schlage_mock_device,
              DoorLock:OperationGet({})
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              schlage_mock_device,
              Battery:Get({})
          )
      )
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(schlage_mock_device.id, "_lock_codes", { ["1"] = "Zach", ["5"] = "Steven" })
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(schlage_mock_device.id, "migrationComplete", true)
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
      test.socket.capability:__expect_send( schlage_mock_device:generate_test_message("main", capabilities.lockUsers.users({{userIndex=1, userName="Zach", userType="guest"}, {userIndex=2, userName="Steven", userType="guest"}}, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send( schlage_mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true,  { visibility = { displayed = false } })))
    end
)

test.run_registered_tests()