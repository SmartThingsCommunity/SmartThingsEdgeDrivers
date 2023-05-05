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
local OnOff = clusters.OnOff
local Level = clusters.Level
local Scenes = clusters.Scenes
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local FrameCtrl = require "st.zigbee.zcl.frame_ctrl"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("switch-level-button.yml"),
      fingerprinted_endpoint_id = 0x01,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Aurora",
          model = "Remote50AU",
          server_clusters = {0x0003, 0x0004, 0x0005, 0x0006, 0x0008, 0x1000, 0x0019}
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
  "On command should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        OnOff.server.commands.On.build_test_rx(mock_device)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

test.register_message_test(
  "Off command should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        OnOff.server.commands.Off.build_test_rx(mock_device)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

test.register_message_test(
  "Capability command On should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on({ state_change = true }))
    }
  }
)

test.register_message_test(
  "Capability command Off should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off({ state_change = true }))
    }
  }
)

test.register_coroutine_test(
  "Move command(MoveStepMode.UP) should be handled",
  function()
    local move_command = Level.server.commands.Move.build_test_rx(mock_device, Level.types.MoveStepMode.DOWN, 0x00,
                                                                  0x00, 0x00)
    local frm_ctrl = FrameCtrl(0x01)
    move_command.body.zcl_header.frame_ctrl = frm_ctrl
    test.socket.zigbee:__queue_receive({ mock_device.id, move_command })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switchLevel.level(10)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switch.switch.on()))
  end
)

test.register_coroutine_test(
  "Move command(MoveStepMode.UP) should be handled",
  function()
    local move_command = Level.server.commands.Move.build_test_rx(mock_device, Level.types.MoveStepMode.UP, 0x00,
                                                                  0x00, 0x00)
    local frm_ctrl = FrameCtrl(0x01)
    move_command.body.zcl_header.frame_ctrl = frm_ctrl
    test.socket.zigbee:__queue_receive({ mock_device.id, move_command })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switchLevel.level(100)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switch.switch.on()))
  end
)

test.register_coroutine_test(
  "Step command(MoveStepMode.DOWN) should be handled",
  function()
    local step_command = Level.server.commands.Step.build_test_rx(mock_device, Level.types.MoveStepMode.DOWN, 0x00,
                                                                  0x0000, 0x00, 0x00)
    local frm_ctrl = FrameCtrl(0x01)
    step_command.body.zcl_header.frame_ctrl = frm_ctrl
    test.socket.zigbee:__queue_receive({ mock_device.id, step_command })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switchLevel.level(90)))
  end
)

test.register_coroutine_test(
  "Step command(MoveStepMode.UP) should be handled",
  function()
    local step_command = Level.server.commands.Step.build_test_rx(mock_device, Level.types.MoveStepMode.UP, 0x00,
                                                                  0x0000, 0x00, 0x00)
    local frm_ctrl = FrameCtrl(0x01)
    step_command.body.zcl_header.frame_ctrl = frm_ctrl
    test.socket.zigbee:__queue_receive({ mock_device.id, step_command })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switchLevel.level(100)))
  end
)


test.register_coroutine_test(
  "StoreScene command should be handled",
  function()
    local scenes_command = Scenes.server.commands.StoreScene.build_test_rx(mock_device, 0x00, 0x00)
    local frm_ctrl = FrameCtrl(0x01)
    scenes_command.body.zcl_header.frame_ctrl = frm_ctrl
    test.socket.zigbee:__queue_receive({ mock_device.id, scenes_command })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.button.held(
                                                                            { state_change = true }
                                                                            )))
  end
)

test.register_coroutine_test(
    "RecallScene command should be handled",
    function()
      local scenes_command = Scenes.server.commands.RecallScene.build_test_rx(mock_device, 0x00, 0x00)
      local frm_ctrl = FrameCtrl(0x01)
      scenes_command.body.zcl_header.frame_ctrl = frm_ctrl
      test.socket.zigbee:__queue_receive({ mock_device.id, scenes_command })
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.button.pushed(
                                            { state_change = true }
                                            )))
    end
)

test.register_coroutine_test(
    "lifecycle configure event should configure device",
    function ()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              OnOff.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              Level.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              Scenes.ID)
                                       })
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.run_registered_tests()
