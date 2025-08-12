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
local PowerConfiguration = clusters.PowerConfiguration
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local BasicInput = clusters.BasicInput
local button_attr = capabilities.button.button
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("button-profile.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "frient A/S",
          model = "MBTZB-110",
          server_clusters = {0x0001,0x0019}
        }
      }
    }
)
zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_message_test(
    "Reported button should be handled: pushed",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, BasicInput.attributes.PresentValue:build_test_attr_report(mock_device, true) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
      }
    }
)

test.register_coroutine_test(
    "Battery Voltage test cases",
    function()
      local battery_test_map = {
          [33] = 100,
          [32] = 100,
          [27] = 50,
          [26] = 30,
          [23] = 10,
          [15] = 0,
          [10] = 0
      }

      for voltage, batt_perc in pairs(battery_test_map) do
        test.socket.zigbee:__queue_receive({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, voltage) })
        test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
        test.wait_for_events()
      end
    end
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes",
    function()
      test.wait_for_events()

      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device,
                                                                             30,
                                                                             21600,
                                                                             1)
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            zigbee_test_utils.build_bind_request(mock_device,
                                                 zigbee_test_utils.mock_hub_eui,
                                                 PowerConfiguration.ID)
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            BasicInput.attributes.PresentValue:configure_reporting(mock_device, 0, 600, 1)
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            zigbee_test_utils.build_bind_request(mock_device,
                                                 zigbee_test_utils.mock_hub_eui,
                                                 BasicInput.ID)
          }
      )
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)


test.run_registered_tests()
