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

local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local tuya_utils = require "tuya_utils"

local IASACE = clusters.IASACE
local PowerConfiguration = clusters.PowerConfiguration

local ZIGBEE_ONE_BUTTON_BATTERY = "one-button-battery"

local mock_device_meian_button = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition(ZIGBEE_ONE_BUTTON_BATTERY .. ".yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "_TZ3000_pkfazisv",
        model = "TS0215A",
        server_clusters = { 0x0500, 0x0001 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device_meian_button)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)


test.register_message_test(
    "Battery percentage report should be handled (button)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_meian_button.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device_meian_button, 55) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_meian_button:generate_test_message("main", capabilities.battery.battery(28))
      }
    }
)

test.register_message_test(
    "Reported button should be handled: pushed",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_meian_button.id, IASACE.server.commands.Emergency.build_test_rx(mock_device_meian_button) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_meian_button:generate_test_message("main", capabilities.button.button.pushed({ state_change = true }))
      }
    }
)

test.register_coroutine_test(
    "Health check should check all relevant attributes",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device_meian_button.id, "added"})
      test.socket.capability:__expect_send(
        mock_device_meian_button:generate_test_message(
          "main",
          capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })
        )
      )
      test.socket.capability:__expect_send(
        mock_device_meian_button:generate_test_message(
          "main",
          capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
        )
      )
      test.socket.capability:__expect_send({
        mock_device_meian_button.id,
        {
          capability_id = "button", component_id = "main",
          attribute_id = "button", state = { value = "pushed" }
        }
      })
      test.socket.zigbee:__expect_send({ mock_device_meian_button.id, tuya_utils.build_tuya_magic_spell_message(mock_device_meian_button) })
      test.socket.zigbee:__expect_send(
          {
            mock_device_meian_button.id,
            PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_meian_button)
          }
      )
    end,
    {
      test_init = function()
        test.mock_device.add_test_device(mock_device_meian_button)
        test.timer.__create_and_queue_test_time_advance_timer(30, "interval", "health_check")
      end
    }
)

test.register_coroutine_test(
    "Refresh necessary attributes",
    function()
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({ mock_device_meian_button.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
      test.socket.zigbee:__expect_send(
        {
          mock_device_meian_button.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_meian_button)
        }
      )

    end
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device_meian_button.id, "added" })
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
        mock_device_meian_button:generate_test_message(
          "main",
          capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })
        )
      )
      test.socket.capability:__expect_send(
        mock_device_meian_button:generate_test_message(
          "main",
          capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
        )
      )
      test.socket.capability:__expect_send({
        mock_device_meian_button.id,
        {
          capability_id = "button", component_id = "main",
          attribute_id = "button", state = { value = "pushed" }
        }
      })
      test.socket.zigbee:__expect_send({ mock_device_meian_button.id, tuya_utils.build_tuya_magic_spell_message(mock_device_meian_button) })
      test.socket.zigbee:__expect_send({
        mock_device_meian_button.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_meian_button)
      })
    end
)

test.run_registered_tests()