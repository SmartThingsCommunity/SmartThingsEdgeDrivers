-- Copyright 2022 SmartThings
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
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.UserCode
local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
--- @type st.zwave.CommandClass.Alarm
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 1 })
local t_utils = require "integration_test.utils"
local zw_test_utils = require "integration_test.zwave_test_utils"
local utils = require "st.utils"

local mock_datastore = require "integration_test.mock_env_datastore"

local json = require "dkjson"

local zwave_lock_endpoints = {
  {
    command_classes = {
      { value = zw.BATTERY },
      { value = DoorLock },
      { value = zw.USER_CODE },
      { value = zw.NOTIFICATION }
    }
  }
}

local lockCodes = {
  ["1"] = "Zach",
  ["2"] = "Steven"
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

local mock_device_no_data = test.mock_device.build_test_zwave_device(
    {
      profile = t_utils.get_profile_definition("base-lock-tamper.yml"),
      data = {}
    }
)

local expect_reload_all_codes_messages = function(dev, lc)
  test.socket.capability:__expect_send(dev:generate_test_message("main",
      capabilities.lockCodes.lockCodes(json.encode(lc), { visibility = { displayed = false } })
  ))
  test.socket.zwave:__expect_send( UserCode:UsersNumberGet({}):build_test_tx(dev.id) )
  test.socket.capability:__expect_send(dev:generate_test_message("main", capabilities.lockCodes.scanCodes("Scanning", { visibility = { displayed = false } })))
  test.socket.zwave:__expect_send( UserCode:Get({ user_identifier = 1 }):build_test_tx(dev.id) )
end

test.register_coroutine_test(
    "Device added data lock codes population",
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
      -- test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device.id, "_lock_codes", { ["1"] = "Zach", ["2"] = "Steven" })
      -- Validate state cache
      assert(mock_device.state_cache.main.lockCodes.lockCodes.value == json.encode(utils.deep_copy(lockCodes)))
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device.id, "migrationComplete", true)
    end
)

test.register_coroutine_test(
    "Device added without data should function",
    function()
      test.mock_device.add_test_device(mock_device_no_data)
      test.socket.device_lifecycle:__queue_receive({ mock_device_no_data.id, "added" })
      expect_reload_all_codes_messages(mock_device_no_data,{})
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device_no_data,
              DoorLock:OperationGet({})
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device_no_data,
              Battery:Get({})
          )
      )
      -- test.socket.capability:__expect_send(mock_device_no_data:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device_no_data.id, "_lock_codes", nil)
      -- Validate state cache
      assert(mock_device_no_data.state_cache.main.lockCodes.lockCodes.value == json.encode({}))
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device_no_data.id, "migrationComplete", nil)
    end
)

test.register_coroutine_test(
    "Device init after added shouldn't change the datastores",
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
      -- test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device.id, "_lock_codes", { ["1"] = "Zach", ["2"] = "Steven" })
      -- Validate state cache
      assert(mock_device.state_cache.main.lockCodes.lockCodes.value == json.encode(utils.deep_copy(lockCodes)))
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device.id, "migrationComplete", true)
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device.id, "_lock_codes", { ["1"] = "Zach", ["2"] = "Steven" })
      -- Validate state cache
      assert(mock_device.state_cache.main.lockCodes.lockCodes.value == json.encode(utils.deep_copy(lockCodes)))
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device.id, "migrationComplete", true)
    end
)

test.register_coroutine_test(
    "Device init after added with no data should update the datastores",
    function()
      test.mock_device.add_test_device(mock_device_no_data)
      test.socket.device_lifecycle:__queue_receive({ mock_device_no_data.id, "added" })
      -- This should happen as the data is empty at this point
      expect_reload_all_codes_messages(mock_device_no_data, {})
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device_no_data,
              DoorLock:OperationGet({})
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device_no_data,
              Battery:Get({})
          )
      )
      -- test.socket.capability:__expect_send(mock_device_no_data:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device_no_data.id, "_lock_codes", nil)
      -- Validate state cache
      assert(mock_device_no_data.state_cache.main.lockCodes.lockCodes.value == json.encode({}))
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device_no_data.id, "migrationComplete", nil)
      test.socket.device_lifecycle():__queue_receive(mock_device_no_data:generate_info_changed(
          {
            data = {
              lockCodes = json.encode(utils.deep_copy(lockCodes))
            }
          }
      ))
      test.socket.device_lifecycle:__queue_receive({ mock_device_no_data.id, "init" })
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device_no_data.id, "_lock_codes", { ["1"] = "Zach", ["2"] = "Steven" })
      -- Validate state cache
      assert(mock_device_no_data.state_cache.main.lockCodes.lockCodes.value == json.encode(utils.deep_copy(lockCodes)))
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device_no_data.id, "migrationComplete", true)
    end
)


test.register_coroutine_test(
    "Device added data lock codes population, should not reload all codes",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(31, "oneshot")
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
      -- test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device.id, "_lock_codes", { ["1"] = "Zach", ["2"] = "Steven" })
      -- Validate state cache
      assert(mock_device.state_cache.main.lockCodes.lockCodes.value == json.encode(utils.deep_copy(lockCodes)))
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device.id, "migrationComplete", true)
      test.wait_for_events()
      test.mock_time.advance_time(35)
      -- Nothing should happen
    end
)

test.run_registered_tests()
