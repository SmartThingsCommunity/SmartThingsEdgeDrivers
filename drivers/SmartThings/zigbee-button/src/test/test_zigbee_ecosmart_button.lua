-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--   http://www.apache.org/licenses/LICENSE-2.0
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
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local Level = clusters.Level
local OnOff = clusters.OnOff
local ColorControl = clusters.ColorControl
local PowerConfiguration = clusters.PowerConfiguration

local button_attr = capabilities.button.button

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("four-buttons-battery.yml"),
    zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "LDS",
      model = "ZBT-CCTSwitch-D0001",
      server_clusters = {0x0001},
      client_clusters = {0x0006, 0x0008, 0x0300}
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
  "Battery percentage report should be handled",
  {
    {
    channel = "zigbee",
    direction = "receive",
    message = { mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 55) }
    },
    {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", capabilities.battery.battery(28))
    }
  }
)

test.register_coroutine_test(
  "added lifecycle event",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })
      )
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.numberOfButtons({ value = 4 }, { visibility = { displayed = false } })
      )
    )

    for button_number = 1, 4 do
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "button" .. button_number,
          capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })
        )
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "button" .. button_number,
          capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
        )
      )
    end
    -- test.socket.capability:__expect_send({
    --   mock_device.id,
    --   {
    --     capability_id = "button", component_id = "main",
    --     attribute_id = "button", state = { value = "pushed" }
    --   }
    -- })

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "button 1 handler",
  function()
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, OnOff.server.commands.Off.build_test_rx(mock_device) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button1", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.socket.zigbee:__queue_receive({ mock_device.id, OnOff.server.commands.On.build_test_rx(mock_device) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button1", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "button 2 handler",
  function()
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, Level.server.commands.Move.build_test_rx(mock_device, 0x00, 0x00) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button2", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "button 3 handler",
  function()
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, ColorControl.server.commands.MoveToColorTemperature.build_test_rx(mock_device, 0x00, 0x00) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button3", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )

    test.socket.zigbee:__queue_receive({ mock_device.id, ColorControl.server.commands.MoveColorTemperature.build_test_rx(mock_device, 0x01, 0x0055, 0x0099, 0x0172, 0x00, 0x00) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button3", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "button 4 handler",
  function()
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, Level.server.commands.MoveToLevelWithOnOff.build_test_rx(mock_device, 0x00, 0x00) })
    test.socket.capability:__expect_send(
        mock_device:generate_test_message("button4", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    -- Ignore this event
    test.socket.zigbee:__queue_receive({ mock_device.id, ColorControl.server.commands.MoveToColorTemperature.build_test_rx(mock_device, 0x00, 0x00) })
    -- Should handle
    test.socket.zigbee:__queue_receive({ mock_device.id, ColorControl.server.commands.MoveToColorTemperature.build_test_rx(mock_device, 0x00, 0x00) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button3", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.socket.zigbee:__queue_receive({ mock_device.id, Level.server.commands.MoveToLevelWithOnOff.build_test_rx(mock_device, 0x00, 0x00) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button4", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    -- Ignore this event
    test.socket.zigbee:__queue_receive({ mock_device.id, ColorControl.server.commands.MoveToColorTemperature.build_test_rx(mock_device, 0x00, 0x00) })
    -- Should handle
    test.socket.zigbee:__queue_receive({ mock_device.id, ColorControl.server.commands.MoveColorTemperature.build_test_rx(mock_device, 0x00, 0x01) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button3", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
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
        PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
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
        PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device,
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
          OnOff.ID)
      }
    )
    test.socket.zigbee:__expect_add_hub_to_group(0x4003)

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.run_registered_tests()
