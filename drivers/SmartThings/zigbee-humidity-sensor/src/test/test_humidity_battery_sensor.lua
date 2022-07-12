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
local clusters = require "st.zigbee.zcl.clusters"
local RelativeHumidity = clusters.RelativeHumidity
local PowerConfiguration = clusters.PowerConfiguration
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("humidity-battery.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "",
          model = "",
          server_clusters = {0x0019, 0x0405, 0x0001, 0xFC08}
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
  "Humidity report should be handled",
  {
     {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_device.id,
          RelativeHumidity.attributes.MeasuredValue:build_test_attr_report(mock_device, 8160)
        }
     },
     {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 50.0 }))
     }
  }
)

test.register_message_test(
  "Humidity report should be handled for 0 value",
  {
     {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_device.id,
          RelativeHumidity.attributes.MeasuredValue:build_test_attr_report(mock_device, 0)
        }
     },
     {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 0.0 }))
     }
  }
)

test.register_message_test(
  "Humidity report should be handled for 100 value",
  {
     {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_device.id,
          RelativeHumidity.attributes.MeasuredValue:build_test_attr_report(mock_device, 65472)
        }
     },
     {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 100.0 }))
     }
  }
)


test.register_coroutine_test(
    "Battery Voltage test cases",
    function()
      local battery_test_map = {
          [4400] = 100.0,
          [3400] = 100.0,
          [3300] = 100.0,
          [3200] = 90.0,
          [2500] = 20.0,
          [2400] = 10.0,
          [2310] = 1.0,
          [2300] = 0.0,
          [22] = 0.0,
          [15] = 0.0
      }
      for voltage, batt_perc in pairs(battery_test_map) do
        test.socket.zigbee:__queue_receive({ mock_device.id, PowerConfiguration.attributes.MainsVoltage:build_test_attr_report(mock_device, voltage) })
        test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
        test.wait_for_events()
      end
    end
)

test.run_registered_tests()
