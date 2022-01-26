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
local clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = clusters.PowerConfiguration
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local contact_battery_profile = t_utils.get_profile_definition("contact-battery-profile.yml")

local mock_device_sengled = test.mock_device.build_test_zigbee_device(
    { profile = contact_battery_profile,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "sengled",
          model = "E1D-G73",
          server_clusters = {}
        }
      }
    }
)
local mock_device_nyce = test.mock_device.build_test_zigbee_device(
    {
      profile = contact_battery_profile,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "NYCE",
          model = "3010",
          server_clusters = {}
        }
      }
    }
)
local mock_device_visonic = test.mock_device.build_test_zigbee_device(
    {
      profile = contact_battery_profile,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Visonic",
          model = "MCT-340 SMA",
          server_clusters = {}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device_sengled)
  test.mock_device.add_test_device(mock_device_nyce)
  test.mock_device.add_test_device(mock_device_visonic)
  zigbee_test_utils.init_noop_health_check_timer()
end

local test_devices = {}
test_devices[mock_device_visonic.id] = mock_device_visonic

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Battery Voltage test cases",
    function()
      -- Manufacturer name:
        --[batteryVoltage] = batteryPercentage
      local battery_test_map = {
        ["Visonic"] = {
          [32] = 100,
          [31] = 100,
          [30] = 100,
          [28] = 78,
          [23] = 22,
          [21] = 0,
          [20] = 0,
          [18] = 0
        }
      }

      for _, mock_device in pairs(test_devices) do
        for voltage, batt_perc in pairs(battery_test_map[mock_device:get_manufacturer()]) do
          test.socket.zigbee:__queue_receive({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, voltage) })
          test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
          test.wait_for_events()
        end
      end
    end
)

test.register_message_test(
    "Battery percentage report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_sengled.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device_sengled,
                                                                                                                    55) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_sengled:generate_test_message("main", capabilities.battery.battery(28))
      }
    }
)

test.register_message_test(
    "Battery percentage report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_nyce.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device_nyce,
                                                                                                                    0xC8) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_nyce:generate_test_message("main", capabilities.battery.battery(100))
      }
    }
)

test.run_registered_tests()
