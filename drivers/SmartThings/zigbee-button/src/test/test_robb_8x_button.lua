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
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local Basic = clusters.Basic
local OnOff = clusters.OnOff
local Level = clusters.Level
local PowerConfiguration = clusters.PowerConfiguration

local button_attr = capabilities.button.button

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("eight-buttons-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "ROBB smarrt",
        model = "ROB_200-007-0",
        server_clusters = { 0x0000, 0x0001, 0x0003, 0x0B05, 0x1000 },
        client_clusters = { 0x0003, 0x0004, 0x0005, 0x0006, 0x0008, 0x0019, 0x0300, 0x1000 }
      },
      [2] = {
        id = 2,
        client_clusters = { 0x0000, 0x0001, 0x0003, 0x0B05, 0x1000 },
        server_clusters = { 0x0003, 0x0004, 0x0005, 0x0006, 0x0008, 0x0019, 0x0300, 0x1000 }
      },
      [3] = {
        id = 3,
        client_clusters = { 0x0000, 0x0001, 0x0003, 0x0B05, 0x1000 },
        server_clusters = { 0x0003, 0x0004, 0x0005, 0x0006, 0x0008, 0x0019, 0x0300, 0x1000 }
      },
      [4] = {
        id = 4,
        client_clusters = { 0x0000, 0x0001, 0x0003, 0x0B05, 0x1000 },
        server_clusters = { 0x0003, 0x0004, 0x0005, 0x0006, 0x0008, 0x0019, 0x0300, 0x1000 }
      }
    }
  }
)

local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Test cases for all 8 buttons beeing pushed",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id,
      zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.On.ID, 0x0000, "\x00", 0x01) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button1", (button_attr.pushed({ state_change = true })))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({ mock_device.id,
      zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.Off.ID, 0x0000, "\x00", 0x01) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button2", (button_attr.pushed({ state_change = true })))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({ mock_device.id,
      zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.On.ID, 0x0000, "\x00", 0x02) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button3", (button_attr.pushed({ state_change = true })))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({ mock_device.id,
      zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.Off.ID, 0x0000, "\x00", 0x02) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button4", (button_attr.pushed({ state_change = true })))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.socket.zigbee:__queue_receive({ mock_device.id,
      zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.On.ID, 0x0000, "\x00", 0x03) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button5", (button_attr.pushed({ state_change = true })))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({ mock_device.id,
      zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.Off.ID, 0x0000, "\x00", 0x03) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button6", (button_attr.pushed({ state_change = true })))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({ mock_device.id,
      zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.On.ID, 0x0000, "\x00", 0x04) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button7", (button_attr.pushed({ state_change = true })))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({ mock_device.id,
      zigbee_test_utils.build_custom_command_id(mock_device, OnOff.ID, OnOff.server.commands.Off.ID, 0x0000, "\x00", 0x04) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button8", (button_attr.pushed({ state_change = true })))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
  end
)

test.register_message_test(
  "Test button1, button3, button5, button7 'up_hold'",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id,
        zigbee_test_utils.build_custom_command_id(mock_device, Level.ID, Level.server.commands.MoveWithOnOff.ID, 0x0000,
          "\x00\x32\x00\x00", 0x01) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button1", capabilities.button.button.up_hold({ state_change = true }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.button.button.up_hold({ state_change = true }))
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id,
        zigbee_test_utils.build_custom_command_id(mock_device, Level.ID, Level.server.commands.MoveWithOnOff.ID, 0x0000,
          "\x00\x32\x00\x00", 0x02) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button3", capabilities.button.button.up_hold({ state_change = true }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.button.button.up_hold({ state_change = true }))
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id,
        zigbee_test_utils.build_custom_command_id(mock_device, Level.ID, Level.server.commands.MoveWithOnOff.ID, 0x0000,
          "\x00\x32\x00\x00", 0x03) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button5", capabilities.button.button.up_hold({ state_change = true }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.button.button.up_hold({ state_change = true }))
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id,
        zigbee_test_utils.build_custom_command_id(mock_device, Level.ID, Level.server.commands.MoveWithOnOff.ID, 0x0000,
          "\x00\x32\x00\x00", 0x04) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button7", capabilities.button.button.up_hold({ state_change = true }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.button.button.up_hold({ state_change = true }))
    }
  }
)

test.register_message_test(
  "Test button2, button4, button6, button8 'down_hold'",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id,
        zigbee_test_utils.build_custom_command_id(mock_device, Level.ID, Level.server.commands.MoveWithOnOff.ID, 0x0000,
          "\x01\x32\x00\x00", 0x01) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button2",
        capabilities.button.button.down_hold({ state_change = true }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.button.button.down_hold({ state_change = true }))
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id,
        zigbee_test_utils.build_custom_command_id(mock_device, Level.ID, Level.server.commands.MoveWithOnOff.ID, 0x0000,
          "\x01\x32\x00\x00", 0x02) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button4",
        capabilities.button.button.down_hold({ state_change = true }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.button.button.down_hold({ state_change = true }))
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id,
        zigbee_test_utils.build_custom_command_id(mock_device, Level.ID, Level.server.commands.MoveWithOnOff.ID, 0x0000,
          "\x01\x32\x00\x00", 0x03) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button6",
        capabilities.button.button.down_hold({ state_change = true }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.button.button.down_hold({ state_change = true }))
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id,
        zigbee_test_utils.build_custom_command_id(mock_device, Level.ID, Level.server.commands.MoveWithOnOff.ID, 0x0000,
          "\x01\x32\x00\x00", 0x04) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button8",
        capabilities.button.button.down_hold({ state_change = true }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.button.button.down_hold({ state_change = true }))
    }
  }
)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function()
    test.socket.environment_update:__queue_receive({ "zigbee",
      { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 30, 21600, 1)
    })

    for endpoint = 1, 4 do
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, OnOff.ID, endpoint)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Level.ID, endpoint)
      })
    end
    test.socket.zigbee:__expect_send({
      mock_device.id,
      OnOff.attributes.OnOff:configure_reporting(mock_device, 0, 600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Basic.attributes.DeviceEnabled:write(mock_device, true)
    })
    test.socket.zigbee:__expect_add_hub_to_group(0xE902)
    test.socket.zigbee:__expect_add_hub_to_group(0xE903)
    test.socket.zigbee:__expect_add_hub_to_group(0xE904)
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "added lifecycle event",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__set_channel_ordering("relaxed")

    for button_name, _ in pairs(mock_device.profile.components) do
      if button_name ~= "main" and (button_name == "button1" or button_name == "button3" or button_name == "button5" or button_name == "button7") then
        test.socket.capability:__expect_send(
          mock_device:generate_test_message(
            button_name,
            capabilities.button.supportedButtonValues({ "pushed", "up_hold" }, { visibility = { displayed = false } })
          )
        )
        test.socket.capability:__expect_send(
          mock_device:generate_test_message(
            button_name,
            capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
          )
        )
      elseif button_name ~= "main" and (button_name == "button2" or button_name == "button4" or button_name == "button6" or button_name == "button8") then
        test.socket.capability:__expect_send(
          mock_device:generate_test_message(
            button_name,
            capabilities.button.supportedButtonValues({ "pushed", "down_hold" }, { visibility = { displayed = false } })
          )
        )
        test.socket.capability:__expect_send(
          mock_device:generate_test_message(
            button_name,
            capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
          )
        )
      else
        test.socket.capability:__expect_send(
          mock_device:generate_test_message(
            "main",
            capabilities.button.supportedButtonValues({ "pushed", "up_hold", "down_hold" },
              { visibility = { displayed = false } })
          )
        )
        test.socket.capability:__expect_send(
          mock_device:generate_test_message(
            "main",
            capabilities.button.numberOfButtons({ value = 8 }, { visibility = { displayed = false } })
          )
        )
      end
    end
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.button.button.pushed({ state_change = false }))
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
    })
  end
)

test.register_message_test(
  "Battery voltage report should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 0xC8) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 0x64) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(50))
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 0) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(0))
    }
  }
)

test.register_coroutine_test(
  "Refresh necessary attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
      }
    )
  end
)

test.run_registered_tests()
