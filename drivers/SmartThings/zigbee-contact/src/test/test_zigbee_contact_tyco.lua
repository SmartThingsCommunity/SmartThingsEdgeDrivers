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
local base64 = require "st.base64"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local contact_battery_profile = t_utils.get_profile_definition("contact-profile.yml")

local mock_device = test.mock_device.build_test_zigbee_device(
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
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Battery Voltage test cases",
    function()
      -- Manufacturer name:
        --[batteryVoltage] = batteryPercentage
      local battery_test_map = {
          [32] = 100,
          [31] = 100,
          [30] = 100,
          [28] = 78,
          [23] = 22,
          [21] = 0,
          [20] = 0,
          [18] = 0
      }

        for voltage, batt_perc in pairs(battery_test_map) do
          test.socket.zigbee:__queue_receive({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, voltage) })
          test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
          test.wait_for_events()
        end
      end
  )
test.register_message_test(
    "Temperature report should be handled (C)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, TemperatureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device,
                                                                                                               2500) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C" }))
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_device.id, capability_id = "temperatureMeasurement", capability_attr_id = "temperature" }
        }
      }
    }
)

test.register_coroutine_test(
    "Handle tempOffset preference infochanged",
    function()
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
      test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({preferences = {tempOffset = -5}}))
      test.wait_for_events()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          TemperatureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 2500)
        }
      )
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C" })))
      mock_device:expect_native_attr_handler_registration("temperatureMeasurement", "temperature")
      test.wait_for_events()
    end
  )


test.run_registered_tests()
