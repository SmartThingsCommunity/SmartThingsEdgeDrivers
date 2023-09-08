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
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff
local Level = clusters.Level
local ColorControl = clusters.ColorControl

local CURRENT_X = "current_x_value"
local CURRENT_Y = "current_y_value"
local Y_TRISTIMULUS_VALUE = "y_tristimulus_value"

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("color-bulb.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "IKEA of Sweden",
        model = "TRADFRI bulb E27 CWS opal 600lm",
        server_clusters = { 0x0006, 0x0008, 0x0300 }
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
        ColorControl.attributes.CurrentX:configure_reporting(mock_device, 1, 3600, 16)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.attributes.CurrentY:configure_reporting(mock_device, 1, 3600, 16)
      }
    )
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Added lifecycle should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentX:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentY:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Refresh necessary attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentX:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentY:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Capability 'switch' command 'on' should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "switch", component = "main", command = "on", args = {} } })

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.On(mock_device) })

    test.wait_for_events()
    test.mock_time.advance_time(2)

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentX:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentY:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Capability 'switch' command 'off' should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "switch", component = "main", command = "off", args = {} } })

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.Off(mock_device) })

    test.wait_for_events()
    test.mock_time.advance_time(2)

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentX:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentY:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Capability 'switchLevel' command 'setLevel' should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 57 } } })

    test.socket.zigbee:__expect_send({ mock_device.id, Level.server.commands.MoveToLevelWithOnOff(mock_device, 144, 0xFFFF) })

    test.wait_for_events()
    test.mock_time.advance_time(2)

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentX:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentY:read(mock_device) })
  end
)

local test_data = {
  { hue = 75, saturation = 65,  x = 0x3E51, y = 0x255D },
  { hue = 75, saturation = nil, x = 0x500F, y = 0x543B }
}

for _, data in ipairs(test_data) do
  test.register_coroutine_test(
    "Set Hue command test",
    function()
      if data.saturation ~= nil then
        test.socket.zigbee:__queue_receive({mock_device.id, ColorControl.attributes.CurrentSaturation:build_test_attr_report(mock_device, math.ceil(data.saturation / 100 * 0xFE))})
        test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorControl.saturation(data.saturation)))
      end

      test.timer.__create_and_queue_test_time_advance_timer(0.2, "oneshot")
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.capability:__queue_receive({mock_device.id,
        {
          capability = "colorControl",
          component = "main",
          command = "setHue",
          args = { data.hue } }
        }
      )

      test.wait_for_events()
      test.mock_time.advance_time(0.2)

      test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.On(mock_device) })
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          ColorControl.commands.MoveToColor(mock_device, data.x, data.y, 0x0000)
        }
      )

      test.wait_for_events()
      test.mock_time.advance_time(2)

      test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentX:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentY:read(mock_device) })
    end
  )
end

test_data = {
  { hue = 75, saturation = 65, x = 0x3E51, y = 0x255D },
  { hue = nil, saturation = 65, x = 0x86EF, y = 0x5465 }
}
for _, data in ipairs(test_data) do
  test.register_coroutine_test(
    "Set Saturation command test",
    function()
      if data.hue ~= nil then
        test.socket.zigbee:__queue_receive({mock_device.id, ColorControl.attributes.CurrentHue:build_test_attr_report(mock_device, math.ceil(data.hue / 100 * 0xFE))})
        test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorControl.hue(data.hue)))
      end

      test.timer.__create_and_queue_test_time_advance_timer(0.2, "oneshot")
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.capability:__queue_receive({mock_device.id,
        {
          capability = "colorControl",
          component = "main",
          command = "setSaturation",
          args = { data.saturation } }
        }
      )

      test.wait_for_events()
      test.mock_time.advance_time(0.2)

      test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.On(mock_device) })
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          ColorControl.commands.MoveToColor(mock_device, data.x, data.y, 0x0000)
        }
      )

      test.wait_for_events()
      test.mock_time.advance_time(2)

      test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentX:read(mock_device) })
      test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentY:read(mock_device) })
    end
  )
end

test.register_coroutine_test(
  "Set Hue/Saturation command test",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(0.2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = "colorControl",
        component = "main",
        command = "setHue",
        args = { 75 } }
      }
    )
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = "colorControl",
        component = "main",
        command = "setSaturation",
        args = { 65 } }
      }
    )

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.On(mock_device) })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.commands.MoveToColor(mock_device, 0x3E51, 0x255D, 0x0000)
      }
    )

    test.wait_for_events()
    test.mock_time.advance_time(2)

    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentX:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentY:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Set Hue followed by Set Color command test",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(0.2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = "colorControl",
        component = "main",
        command = "setHue",
        args = { 75 } }
      }
    )
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = "colorControl",
        component = "main",
        command = "setColor",
        args = { { hue = 20, saturation = 100 } } }
      }
    )

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.On(mock_device) })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.commands.MoveToColor(mock_device, 0x6239, 0x8896, 0x0000)
      }
    )

    test.wait_for_events()
    test.mock_time.advance_time(2)

    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentX:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentY:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Set Color command test",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "colorControl", component = "main", command = "setColor", args = { { hue = 75, saturation = 65 } } } })

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.server.commands.On(mock_device) })

    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.commands.MoveToColor(mock_device, 0x3E51, 0x255D, 0x0000)
      }
    )

    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentX:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentY:read(mock_device) })
  end
)

test.register_coroutine_test(
  "CurrentX attr report should be handled",
  function()
    mock_device:set_field(CURRENT_Y, 9565)
    mock_device:set_field(Y_TRISTIMULUS_VALUE, 0.23191276511572)
    test.socket.zigbee:__queue_receive({ mock_device.id, ColorControl.attributes.CurrentX:build_test_attr_report(mock_device, 15953) })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorControl.hue(75)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorControl.saturation(65)))
  end
)

test.register_coroutine_test(
  "CurrentY attr report should be handled",
  function()
    mock_device:set_field(CURRENT_X, 15953)
    mock_device:set_field(Y_TRISTIMULUS_VALUE, 0.23191276511572)
    test.socket.zigbee:__queue_receive({ mock_device.id, ColorControl.attributes.CurrentY:build_test_attr_report(mock_device, 9565) })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorControl.hue(75)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorControl.saturation(65)))
  end
)

test.register_coroutine_test(
  "CurrentX and CurrentY attr report should be handled",
  function()
    mock_device:set_field(Y_TRISTIMULUS_VALUE, 0.23191276511572)
    test.socket.zigbee:__queue_receive({ mock_device.id, ColorControl.attributes.CurrentX:build_test_attr_report(mock_device, 15953) })
    test.socket.zigbee:__queue_receive({ mock_device.id, ColorControl.attributes.CurrentY:build_test_attr_report(mock_device, 9565) })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorControl.hue(75)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorControl.saturation(65)))
  end
)

test.register_coroutine_test(
  "CurrentY and CurrentX attr report should be handled",
  function()
    mock_device:set_field(Y_TRISTIMULUS_VALUE, 0.23191276511572)
    test.socket.zigbee:__queue_receive({ mock_device.id, ColorControl.attributes.CurrentY:build_test_attr_report(mock_device, 9565) })
    test.socket.zigbee:__queue_receive({ mock_device.id, ColorControl.attributes.CurrentX:build_test_attr_report(mock_device, 15953) })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorControl.hue(75)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorControl.saturation(65)))
  end
)

test.run_registered_tests()
