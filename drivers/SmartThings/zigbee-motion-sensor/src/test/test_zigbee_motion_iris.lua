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
local capabilities = require "st.capabilities"
local IASZone = clusters.IASZone
local TemperatureMeasurement = clusters.TemperatureMeasurement
local RelativeHumidity = clusters.RelativeHumidity
local PowerConfiguration = clusters.PowerConfiguration
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("motion-humidity-temp-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "iMagic by GreatStar",
        model = "1117-S",
        server_clusters = {0x0001, 0x0402, 0x0405, 0x0500}
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


test.register_coroutine_test(
  "Battery Voltage test cases",
  function()
    -- Manufacturer name:
      --[batteryVoltage] = batteryPercentage
    local battery_test_map = {
      ["iMagic by GreatStar"] = {
        [28] = 100,
        [27] = 100,
        [26] = 67,
        [25] = 33,
        [24] = 0,
        [23] = 0
      }
    }

    for voltage, batt_perc in pairs(battery_test_map[mock_device:get_manufacturer()]) do
      test.socket.zigbee:__queue_receive({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, voltage) })
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
      test.wait_for_events()
    end
  end
)

test.register_message_test(
  "Refresh should read all necessary attributes",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {mock_device.id, "added"}
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "refresh", component = "main", command = "refresh", args = {} }
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
          mock_device.id,
          PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
          mock_device.id,
          TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
          mock_device.id,
          RelativeHumidity.attributes.MeasuredValue:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
          mock_device.id,
          IASZone.attributes.ZoneStatus:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
          mock_device.id,
          TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 30, 600, 100)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
          mock_device.id,
          IASZone.attributes.ZoneStatus:configure_reporting(mock_device, 0xFFFF, 0x0000, 0)
      }
    },
  },
  {
      inner_block_ordering = "relaxed"
  }
)

test.run_registered_tests()
