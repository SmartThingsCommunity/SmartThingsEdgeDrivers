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

local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff
local Level = clusters.Level
local ColorControl = clusters.ColorControl

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("color-temp-bulb.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "IKEA of Sweden",
        model = "TRADFRI bulb E26 WS clear 950lm",
        server_clusters = { 0x0006, 0x0008, 0x0300 },
        profile_id = 0xC05E,
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
  "Refresh necessary attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
  end
)

test.register_coroutine_test(
    "ZLL periodic poll should occur",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
      test.wait_for_events()

      test.mock_time.advance_time(50000)
      test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
      test.wait_for_events()
    end,
    {
      test_init = function()
        test.mock_device.add_test_device(mock_device)
        test.timer.__create_and_queue_test_time_advance_timer(30, "interval", "polling")
      end
    }
)

test.register_coroutine_test(
  "Switch command on should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "switch", component = "main", command = "on", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.On(mock_device)})
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Switch command off should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "switch", component = "main", command = "off", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.Off(mock_device)})
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
  end
)

test.register_coroutine_test(
  "SwitchLevel command setLevel should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "switchLevel", component = "main", command = "setLevel", args = {50} } })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.commands.MoveToLevelWithOnOff(mock_device, math.floor(50 / 100.0 * 254), 0xFFFF)})
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
  end
)

test.register_coroutine_test(
  "ColorTemperature command setColorTemperature should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = {200} } })
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.On(mock_device)})
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.commands.MoveToColorTemperature(mock_device, 5000, 0x0000)})
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
  end
)

test.run_registered_tests()
