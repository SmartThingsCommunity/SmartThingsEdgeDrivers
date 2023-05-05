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
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = clusters.PowerConfiguration
local DoorLock = clusters.DoorLock
local Alarm = clusters.Alarms

local json = require "st.json"

local mock_datastore = require "integration_test.mock_env_datastore"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("base-lock.yml"),
      data = {
        lockCodes = json.encode({
          ["1"] = "Zach",
          ["2"] = "Steven"
        })
      }
    }
)

local mock_device_no_data = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("base-lock.yml"),
      data = {}
    }
)
zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Device added data lock codes population",
    function()
      test.mock_device.add_test_device(mock_device)
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
      test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, Alarm.attributes.AlarmCount:read(mock_device) })
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device.id, "lockCodes", { ["1"] = "Zach", ["2"] = "Steven" })
      -- Validate state cache
      mock_datastore.__assert_device_store_contains(mock_device.id, "__state_cache",
          {
            main = {
              lockCodes = {
                lockCodes = {value = json.encode({ ["1"] = "Zach", ["2"] = "Steven" }) }
              }
            }
          }
      )
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device.id, "migrationComplete", true)
    end
)

test.register_coroutine_test(
    "Device added without data should function",
    function()
      test.mock_device.add_test_device(mock_device_no_data)
      test.socket.device_lifecycle:__queue_receive({ mock_device_no_data.id, "added" })
      test.socket.zigbee:__expect_send({ mock_device_no_data.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_no_data) })
      test.socket.zigbee:__expect_send({ mock_device_no_data.id, DoorLock.attributes.LockState:read(mock_device_no_data) })
      test.socket.zigbee:__expect_send({ mock_device_no_data.id, Alarm.attributes.AlarmCount:read(mock_device_no_data) })
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device.id, "lockCodes", nil)
      -- Validate state cache
      mock_datastore.__assert_device_store_contains(mock_device.id, "__state_cache", nil)
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device.id, "migrationComplete", nil)
    end
)

test.register_coroutine_test(
    "Device init after added shouldn't change the datastores",
    function()
      test.mock_device.add_test_device(mock_device)
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
      test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, Alarm.attributes.AlarmCount:read(mock_device) })
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device.id, "lockCodes", { ["1"] = "Zach", ["2"] = "Steven" })
      -- Validate state cache
      mock_datastore.__assert_device_store_contains(mock_device.id, "__state_cache",
          {
            main = {
              lockCodes = {
                lockCodes = {value = json.encode({ ["1"] = "Zach", ["2"] = "Steven" }) }
              }
            }
          }
      )
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device.id, "migrationComplete", true)
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device.id, "lockCodes", { ["1"] = "Zach", ["2"] = "Steven" })
      -- Validate state cache
      mock_datastore.__assert_device_store_contains(mock_device.id, "__state_cache",
          {
            main = {
              lockCodes = {
                lockCodes = {value = json.encode({ ["1"] = "Zach", ["2"] = "Steven" }) }
              }
            }
          }
      )
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device.id, "migrationComplete", true)
    end
)

test.register_coroutine_test(
    "Device init with new data should populate fields",
    function()
      test.mock_device.add_test_device(mock_device_no_data)
      test.socket.device_lifecycle:__queue_receive({ mock_device_no_data.id, "added" })
      test.socket.zigbee:__expect_send({ mock_device_no_data.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_no_data) })
      test.socket.zigbee:__expect_send({ mock_device_no_data.id, DoorLock.attributes.LockState:read(mock_device_no_data) })
      test.socket.zigbee:__expect_send({ mock_device_no_data.id, Alarm.attributes.AlarmCount:read(mock_device_no_data) })
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device_no_data.id, "lockCodes", nil)
      -- Validate state cache
      mock_datastore.__assert_device_store_contains(mock_device_no_data.id, "__state_cache", {})
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device_no_data.id, "migrationComplete", nil)
      test.socket.device_lifecycle():__queue_receive(mock_device_no_data:generate_info_changed(
          {
            data = {
              lockCodes = json.encode({ ["1"] = "Zach", ["2"] = "Steven" })
            }
          }
      ))
      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive({ mock_device_no_data.id, "init" })
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device_no_data.id, "lockCodes", { ["1"] = "Zach", ["2"] = "Steven" })
      -- Validate state cache
      mock_datastore.__assert_device_store_contains(mock_device_no_data.id, "__state_cache",
          {
            main = {
              lockCodes = {
                lockCodes = {value = json.encode({ ["1"] = "Zach", ["2"] = "Steven" }) }
              }
            }
          }
      )
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device_no_data.id, "migrationComplete", true)
    end
)

test.register_coroutine_test(
    "Device added data lock codes population, device response produces no events",
    function()
      test.mock_device.add_test_device(mock_device)
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
      test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, Alarm.attributes.AlarmCount:read(mock_device) })
      test.wait_for_events()
      -- Validate lockCodes field
      mock_datastore.__assert_device_store_contains(mock_device.id, "lockCodes", { ["1"] = "Zach", ["2"] = "Steven" })
      -- Validate state cache
      mock_datastore.__assert_device_store_contains(mock_device.id, "__state_cache",
          {
            main = {
              lockCodes = {
                lockCodes = {value = json.encode({ ["1"] = "Zach", ["2"] = "Steven" }) }
              }
            }
          }
      )
      -- Validate migration complete flag
      mock_datastore.__assert_device_store_contains(mock_device.id, "migrationComplete", true)
      test.wait_for_events()

      -- run do_configure step after added and verify no refresh all codes
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__expect_send({ mock_device.id, zigbee_test_utils.build_bind_request(mock_device,
          zigbee_test_utils.mock_hub_eui,
          PowerConfiguration.ID) })
      test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device,
          600,
          21600,
          1) })
      test.socket.zigbee:__expect_send({ mock_device.id, zigbee_test_utils.build_bind_request(mock_device,
          zigbee_test_utils.mock_hub_eui,
          DoorLock.ID) })
      test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:configure_reporting(mock_device,
          0,
          3600,
          0) })
      test.socket.zigbee:__expect_send({ mock_device.id, zigbee_test_utils.build_bind_request(mock_device,
          zigbee_test_utils.mock_hub_eui,
          Alarm.ID) })
      test.socket.zigbee:__expect_send({ mock_device.id, Alarm.attributes.AlarmCount:configure_reporting(mock_device,
          0,
          21600,
          0) })

      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
      -- Validate migration reload skipped datastore
      test.wait_for_events()
      mock_datastore.__assert_device_store_contains(mock_device.id, "migrationReloadSkipped", true)
      -- Verify the timer doesn't fire as it wasn't created
      test.mock_time.advance_time(4)
      test.wait_for_events()
    end
)


test.run_registered_tests()
