-- Copyright 2021 SmartThings
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
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local PowerConfiguration = clusters.PowerConfiguration
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local OccupancyAttribute = clusters.OccupancySensing.attributes.Occupancy

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("motion-battery.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "NYCE",
          model = "3045",
          server_clusters = {}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Reported motion should be handled: active",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OccupancyAttribute:build_test_attr_report(mock_device, 0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "Reported motion should be handled: active",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OccupancyAttribute:build_test_attr_report(mock_device, 0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    }
)

test.register_coroutine_test(
    "Battery Voltage test cases",
    function()
      -- Manufacturer name:
        --[batteryVoltage] = batteryPercentage
      local battery_test_map = {
        ["NYCE"] = {
          [33] = 100,
          [32] = 100,
          [31] = 100,
          [29] = 89,
          [26] = 56,
          [23] = 22,
          [15] = 0,
          [10] = 0
        }
      }

      for voltage, batt_perc in pairs(battery_test_map[mock_device:get_manufacturer()]) do
        test.socket.zigbee:__queue_receive({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, voltage) })
        test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
        test.wait_for_events()
      end
    end
  )

test.run_registered_tests()
