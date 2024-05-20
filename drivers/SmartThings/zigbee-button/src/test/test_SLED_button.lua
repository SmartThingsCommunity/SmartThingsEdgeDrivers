-- Copyright 2024 SmartThings
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
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"

local Level = clusters.Level
local OnOff = clusters.OnOff
local ColorControl = clusters.ColorControl
local button_attr = capabilities.button.button

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("SLED-three-buttons.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Samsung Electronics",
        model = "SAMSUNG-ITM-Z-005",
        server_clusters = {0x0001, 0x0006, 0x0008, 0x0300}
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
  "Reported button should be handled: pushed true",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, OnOff.server.commands.On.build_test_rx(mock_device) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button1", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({ mock_device.id, OnOff.server.commands.Off.build_test_rx(mock_device) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button2", button_attr.pushed({ state_change = true }))
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({ mock_device.id, OnOff.server.commands.Toggle.build_test_rx(mock_device) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button3", button_attr.pushed({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "Reported button should be handled: held true",
  function()
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({ mock_device.id, Level.server.commands.MoveWithOnOff.build_test_rx(mock_device, 0x00, 0x00) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button1", button_attr.held({ state_change = true }))
    )
    test.socket.zigbee:__queue_receive({ mock_device.id, Level.server.commands.Move.build_test_rx(mock_device, 0x00, 0x00) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button2", button_attr.held({ state_change = true }))
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({ mock_device.id, ColorControl.server.commands.MoveToColorTemperature.build_test_rx(mock_device, 0x00, 0x00) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button3", button_attr.held({ state_change = true }))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Handle doConfigure lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, OnOff.ID)
      })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.run_registered_tests()
