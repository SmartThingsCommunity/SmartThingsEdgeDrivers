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

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration

local button = capabilities.button

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("one-button-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "eWeLink",
        model = "WB01",
        server_clusters = { 0x0001 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "added lifecycle event",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.supportedButtonValues({ "pushed", "held", "double" }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
      )
    )
    -- test.socket.capability:__expect_send(
    --   mock_device:generate_test_message("main", button.button.pushed({ state_change = false }))
    -- )
  end
)

test.register_coroutine_test(
  "doConfigure lifecycle event",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({ mock_device.id, zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, OnOff.ID) })
    test.socket.zigbee:__expect_send({ mock_device.id, zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID) })
    test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 30, 21600, 1) })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "OnOff cluster On command should result with sending double event",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      OnOff.server.commands.On.build_test_rx(mock_device)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button.button.double({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "OnOff cluster Off command should result with sending held event",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      OnOff.server.commands.Off.build_test_rx(mock_device)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button.button.held({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "OnOff cluster any command (except On or Off) should result with sending pushed event",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      OnOff.server.commands.OffWithEffect.build_test_rx(mock_device, 0x00, 0x00)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button.button.pushed({ state_change = true }))
    )

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      OnOff.server.commands.OnWithRecallGlobalScene.build_test_rx(mock_device)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button.button.pushed({ state_change = true }))
    )

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      OnOff.server.commands.OnWithTimedOff.build_test_rx(mock_device, 0x01, 0x00, 0x00)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button.button.pushed({ state_change = true }))
    )

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      OnOff.server.commands.Toggle.build_test_rx(mock_device)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button.button.pushed({ state_change = true }))
    )
  end
)

test.run_registered_tests()