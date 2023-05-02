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
local t_utils = require "integration_test.utils"
local clusters = require "st.zigbee.zcl.clusters"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff
local Level = clusters.Level
local ColorControl = clusters.ColorControl

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("rgbw-bulb.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "innr",
        model = "RB 250 C",
        server_clusters = {0x0006, 0x0008, 0x0300}
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
  "Configure should configure all necessary attributes and refresh device",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")

    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, OnOff.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Level.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, ColorControl.ID)
    })

    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        OnOff.attributes.OnOff:configure_reporting(mock_device, 0, 300, 1)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        Level.attributes.CurrentLevel:configure_reporting(mock_device, 1, 3600, 1)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.attributes.ColorTemperatureMireds:configure_reporting(mock_device, 1, 3600, 16)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.attributes.CurrentHue:configure_reporting(mock_device, 1, 3600, 16)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.attributes.CurrentSaturation:configure_reporting(mock_device, 1, 3600, 16)
      }
    )

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentHue:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentSaturation:read(mock_device) })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_message_test(
  "Refresh should read all necessary attributes",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {mock_device.id, {capability = "refresh", component = "main", command = "refresh", args = {}}}
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        OnOff.attributes.OnOff:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        Level.attributes.CurrentLevel:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        ColorControl.attributes.ColorTemperatureMireds:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        ColorControl.attributes.CurrentHue:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        ColorControl.attributes.CurrentSaturation:read(mock_device)
      }
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
  "Set Hue command test",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "colorControl", component = "main", command = "setHue", args = { 50 } } })

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.On(mock_device) })

    local hue = math.floor((50 * 0xFE) / 100.0 + 0.5)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.server.commands.MoveToHue(mock_device, hue, 0x00, 0x0000)
      }
    )

    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({mock_device.id, ColorControl.attributes.CurrentHue:read(mock_device)})
  end
)

test.register_coroutine_test(
  "Set Saturation command test",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "colorControl", component = "main", command = "setSaturation", args = { 50 } } })

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.On(mock_device) })

    local saturation = math.floor((50 * 0xFE) / 100.0 + 0.5)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.server.commands.MoveToSaturation(mock_device, saturation, 0x0000)
      }
    )

    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({mock_device.id, ColorControl.attributes.CurrentSaturation:read(mock_device)})
  end
)

test.register_coroutine_test(
  "Set Color command test",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "colorControl", component = "main", command = "setColor", args = { { hue = 50, saturation = 50 } } } })

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.server.commands.On(mock_device) })

    local hue = math.floor((50 * 0xFE) / 100.0 + 0.5)
    local sat = math.floor((50 * 0xFE) / 100.0 + 0.5)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.server.commands.MoveToHueAndSaturation(mock_device, hue, sat, 0x0000)
      }
    )

    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({mock_device.id, ColorControl.attributes.CurrentHue:read(mock_device)})
    test.socket.zigbee:__expect_send({mock_device.id, ColorControl.attributes.CurrentSaturation:read(mock_device)})
  end
)

test.register_coroutine_test(
  "Set Saturation command test",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = { 200 } } })

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.On(mock_device) })

    local color_temp_mireds = math.floor(1000000 / 200)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.server.commands.MoveToColorTemperature(mock_device, color_temp_mireds, 0x0000)
      }
    )

    test.wait_for_events()

    test.mock_time.advance_time(1)
    test.socket.zigbee:__expect_send({mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device)})
  end
)

test.register_coroutine_test(
  "Added lifecycle event should set color temperature",
  function ()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.commands.MoveToColorTemperature(mock_device, 200, 0)
      }
    )
  end
)

test.run_registered_tests()
