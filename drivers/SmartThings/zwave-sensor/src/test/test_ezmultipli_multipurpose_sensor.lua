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
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"
local utils = require "st.utils"
local capabilities = require "st.capabilities"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local SwitchColor = (require "st.zwave.CommandClass.SwitchColor")({ version = 1 })


local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.CONFIGURATION},
      {value = zw.SWITCH_COLOR}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("motion-switch-color-illuminance-temperature.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x001E,
  zwave_product_type = 0x0004,
  zwave_product_id = 0x0001,
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Basic report with 0xFF should be handled to switch.on()",
  {
    {
    channel = "zwave",
    direction = "receive",
    message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0xFF })) }
    },
    {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Basic report with 0x00 should be handled to switch.off(), colorCotrol.hue() and colorControl.saturation()",
  {
    {
    channel = "zwave",
    direction = "receive",
    message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0x00 })) }
    },
    {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", capabilities.colorControl.hue(0))
    },
    {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", capabilities.colorControl.saturation(0))
    },
    {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

do
  local hue = math.random(0, 100)
  local sat = math.random(0, 100)
  local r, g, b = utils.hsl_to_rgb(hue, sat)
  r = (r >= 191) and 255 or 0
  g = (g >= 191) and 255 or 0
  b = (b >= 191) and 255 or 0
  test.register_coroutine_test(
    "Color Control capability setColor commands should evoke the correct Z-Wave SETs and GETs",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({mock_device.id, { capability = "colorControl", command = "setColor", args = { { hue = hue, saturation = sat, level = 100 } } } })

      test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchColor:Set({
          color_components = {
            { color_component_id = SwitchColor.color_component_id.RED, value = r },
            { color_component_id = SwitchColor.color_component_id.GREEN, value = g },
            { color_component_id = SwitchColor.color_component_id.BLUE, value = b },
          }
        })
      ))

      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.RED })
      ))
    end
  )
end

do
  local hue = math.random(0, 100)
  local sat = 100
  local r, g, b = utils.hsl_to_rgb(hue, sat)
  r = (r >= 191) and 255 or 0
  g = (g >= 191) and 255 or 0
  b = (b >= 191) and 255 or 0
  test.register_coroutine_test(
    "Color Control capability setColor commands should evoke the correct Z-Wave SETs and GETs",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({mock_device.id, { capability = "colorControl", command = "setColor", args = { { hue = hue, saturation = sat } } } })

      test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchColor:Set({
          color_components = {
            { color_component_id = SwitchColor.color_component_id.RED, value = r },
            { color_component_id = SwitchColor.color_component_id.GREEN, value = g },
            { color_component_id = SwitchColor.color_component_id.BLUE, value = b },
          }
        })
      ))

      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.RED })
      ))
    end
  )
end

test.register_coroutine_test(
  "infoChanged() and doConfigure() should send the SET command for Configuation value",
  function()

    local onTime = math.random(0,127)
    local onLevel = math.random(0,100) - 1
    local liteMin = math.random(0,127)
    local tempMin = math.random(0,127)
    local tempAdj = math.random(1,256) - 128

    test.socket.zwave:__set_channel_ordering("relaxed")

    test.wait_for_events()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed(
      {
        preferences = {
          onTime = onTime,
          onLevel = onLevel,
          liteMin = liteMin,
          tempMin = tempMin,
          tempAdj = tempAdj
        }
      }
    ))

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({parameter_number=1, size=1, configuration_value=onTime})
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({parameter_number=2, size=1, configuration_value=onLevel})
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({parameter_number=3, size=1, configuration_value=liteMin})
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({parameter_number=4, size=1, configuration_value=tempMin})
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({parameter_number=5, size=1, configuration_value=tempAdj})
      )
    )

    test.socket.device_lifecycle():__queue_receive({mock_device.id, "doConfigure"})

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({parameter_number=1, size=1, configuration_value=onTime})
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({parameter_number=2, size=1, configuration_value=onLevel})
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({parameter_number=3, size=1, configuration_value=liteMin})
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({parameter_number=4, size=1, configuration_value=tempMin})
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({parameter_number=5, size=1, configuration_value=tempAdj})
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Basic:Get({})
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.RED })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.GREEN })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.BLUE })
      )
    )

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.run_registered_tests()
