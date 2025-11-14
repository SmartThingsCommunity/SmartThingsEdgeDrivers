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

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local IASZone = clusters.IASZone
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local ZoneStatusAttribute = IASZone.attributes.ZoneStatus
local button_attr = capabilities.button.button

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("twelve-buttons-without-main-button.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Linxura",
          model = "Aura Smart Button",
          server_clusters = {0x0001, 0x0500, 0x0000}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "added lifecycle event",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    for button_name, _ in pairs(mock_device.profile.components) do
      if button_name ~= "main" then
        test.socket.capability:__expect_send(
          mock_device:generate_test_message(
            button_name,
            capabilities.button.supportedButtonValues({ "pushed", "held", "double" }, { visibility = { displayed = false } })
          )
        )
        test.socket.capability:__expect_send(
          mock_device:generate_test_message(
            button_name,
            capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
          )
        )
      end
    end

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.wait_for_events()
    end
)

test.register_coroutine_test(
    "Test cases for Buttons Pushed",
    function()
      for var = 0, 11 do
        test.socket.zigbee:__queue_receive({
            mock_device.id,
            ZoneStatusAttribute:build_test_attr_report(mock_device, 1 + var * 6)
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(string.format("button%d", var + 1), button_attr.pushed({ state_change = true }))
        )
        test.wait_for_events()
      end
    end
)

test.register_coroutine_test(
    "Test cases for Buttons Double",
    function()
        for var = 0, 11 do
          test.socket.zigbee:__queue_receive({
              mock_device.id,
              ZoneStatusAttribute:build_test_attr_report(mock_device, 3 + var * 6)
          })
          test.socket.capability:__expect_send(
              mock_device:generate_test_message(string.format("button%d", var + 1), button_attr.double({ state_change = true }))
          )
          test.wait_for_events()
        end
    end
)


test.register_coroutine_test(
    "Test cases for Buttons Held",
    function()
        for var = 0, 11 do
          test.socket.zigbee:__queue_receive({
              mock_device.id,
              ZoneStatusAttribute:build_test_attr_report(mock_device, 5 + var * 6)
          })
          test.socket.capability:__expect_send(
              mock_device:generate_test_message(string.format("button%d", var + 1), button_attr.held({ state_change = true }))
          )
          test.wait_for_events()
        end
    end
)


test.run_registered_tests()