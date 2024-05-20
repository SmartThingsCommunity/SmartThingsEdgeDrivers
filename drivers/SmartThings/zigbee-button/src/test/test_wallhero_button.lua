-- Copyright 2023 SmartThings
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

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local Scenes = clusters.Scenes

local button_attr = capabilities.button.button

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("thirty-buttons.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "WALL HERO",
        model = "ACL-401SCA4",
        server_clusters = {0x0000 , 0x0003 , 0x0004 , 0x0005 , 0x0006}
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
  "RecallScene command should be handled",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x01) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button1", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x02) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button2", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x03) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button3", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x04) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button4", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x05) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button5", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x06) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button6", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x07) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button7", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x08) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button8", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x09) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button9", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x0A) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button10", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x0B) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button11", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x0C) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button12", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x0D) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button13", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x0E) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button14", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x0F) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button15", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x10) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button16", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x11) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button17", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x12) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button18", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x13) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button19", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x14) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button20", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x15) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button21", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x16) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button22", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x17) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button23", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x18) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button24", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x19) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button25", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x1A) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button26", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x1B) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button27", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x1C) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button28", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x1D) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button29", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x1E) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button30", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({ mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, Scenes.ID, Scenes.server.commands.RecallScene.ID, 0x0000, "\x05\x00\x00\x00\x05\x00", 0x1F) })
    test.wait_for_events()
  end
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
        capabilities.button.numberOfButtons({ value = 30 }, { visibility = { displayed = false } })
      )
    )
    for _, component in pairs(mock_device.profile.components) do
      if component.id ~= "main" then
        test.socket.capability:__expect_send(
          mock_device:generate_test_message(
            component.id,
            capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })
          )
        )
        test.socket.capability:__expect_send(
          mock_device:generate_test_message(
            component.id,
            capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
          )
        )
      end
    end
    test.socket:set_time_advance_per_select(0.1)
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.wait_for_events()
  end
)

test.run_registered_tests()
