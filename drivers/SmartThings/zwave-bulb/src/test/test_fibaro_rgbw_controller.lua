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
local constants = require "st.zwave.constants"
local utils = require "st.utils"
local t_utils = require "integration_test.utils"
local zw_test_utils = require "integration_test.zwave_test_utils"
local cc = require "st.zwave.CommandClass"
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=2 })
local SwitchColor = (require "st.zwave.CommandClass.SwitchColor")({ version=1 })
local Meter = (require "st.zwave.CommandClass.Meter")({ version=3 })
local Association = (require "st.zwave.CommandClass.Association")({ version=2 })

-- supported comand classes
local fibaro_rgbw_controller_endpoints = {
  {
    command_classes = {
      {value = cc.SWITCH_MULTILEVEL},
      {value = cc.SWITCH_COLOR}
    }
  }
}

local mock_fibaro_rgbw_controller = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("fibaro-rgbw-controller.yml"),
  zwave_endpoints = fibaro_rgbw_controller_endpoints,
  zwave_manufacturer_id = 0x010F, -- Fibaro
  zwave_product_type = 0x0900,
  zwave_product_id = 0x2000,
})

local function test_init()
  test.mock_device.add_test_device(mock_fibaro_rgbw_controller)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Refresh capability refresh commands should evoke Z-Wave GETs to bootstrap state",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_fibaro_rgbw_controller.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchMultilevel:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.RED })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.GREEN })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.BLUE })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.WARM_WHITE })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.COLD_WHITE })
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Device should be polled with refresh right after inclusion",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_fibaro_rgbw_controller.id, "added" }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        Association:Set({grouping_identifier = 5, node_ids = {}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchMultilevel:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.RED })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.GREEN })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.BLUE })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.WARM_WHITE })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.COLD_WHITE })
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
  "Switch capability off command on component white should evoke the correct Z-Wave SETs and GETs from SwitchColor CC",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_fibaro_rgbw_controller.id,
      { capability = "switch", component = "white", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchColor:Set({
          color_components = {
            { color_component_id=SwitchColor.color_component_id.WARM_WHITE, value = 0 },
          }
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(constants.DEFAULT_GET_STATUS_DELAY)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.WARM_WHITE })
      )
    )
  end
)

test.register_coroutine_test(
  "Switch capability on command on component white should evoke the correct Z-Wave SETs and GETs from SwitchColor CC",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_fibaro_rgbw_controller.id,
      { capability = "switch", component = "white", command = "on", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchColor:Set({
          color_components = {
            { color_component_id=SwitchColor.color_component_id.WARM_WHITE, value = 255 },
          }
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(constants.DEFAULT_GET_STATUS_DELAY)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.WARM_WHITE })
      )
    )
  end
)

test.register_message_test(
  "Z-Wave SwitchMultilevel reports with value-off should evoke Switch capability off events",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_fibaro_rgbw_controller.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchMultilevel:Report({
            value = SwitchMultilevel.value.OFF_DISABLE
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_rgbw_controller:generate_test_message("white", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_rgbw_controller:generate_test_message("rgb", capabilities.switch.switch.off())
    }
  },
  {
  }
)

test.register_coroutine_test(
  "Switch Level capability setLevel commands should evoke the correct Z-Wave SETs and GETs",
  function()
    local level = math.random(0, 100)
    test.timer.__create_and_queue_test_time_advance_timer(constants.MIN_DIMMING_GET_STATUS_DELAY, "oneshot")
    test.socket.capability:__queue_receive({
      mock_fibaro_rgbw_controller.id,
      { capability = "switchLevel", command = "setLevel", args = { level } }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
        SwitchMultilevel:Set({
          value = utils.clamp_value(level, 1, 99),
          duration = constants.DEFAULT_DIMMING_DURATION
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(constants.MIN_DIMMING_GET_STATUS_DELAY)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_rgbw_controller,
          SwitchMultilevel:Get({})
      )
    )
  end,
  {
  }
)

test.register_message_test(
  "Power meter report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_fibaro_rgbw_controller.id, zw_test_utils.zwave_test_build_receive_command(
        Meter:Report({
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = 27
        })
      )}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_rgbw_controller:generate_test_message("main", capabilities.powerMeter.power({ value = 27, unit = "W" }))
    }
  }
)

do
  local level = math.random(1,100)
  test.register_message_test(
    "Z-Wave SwitchMultilevel reports with non-zero values should evoke Switch Level capability events",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_fibaro_rgbw_controller.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchMultilevel:Report({
              value = level
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_rgbw_controller:generate_test_message("main", capabilities.switchLevel.level(level))
      }
    }
  )
end

do
  local hue = math.random(0, 100)
  local sat = math.random(0, 100)
  local r, g, b = utils.hsl_to_rgb(hue, sat)
  test.register_coroutine_test(
    "Color Control capability setColor commands should evoke the correct Z-Wave SETs and GETs",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_fibaro_rgbw_controller.id,
        {
          capability = "colorControl",
          command = "setColor",
          args = {
            {
              hue = hue,
              saturation = sat
            }
          }
        }
      })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_rgbw_controller,
          SwitchColor:Set({
            color_components = {
              { color_component_id = SwitchColor.color_component_id.RED, value = r },
              { color_component_id = SwitchColor.color_component_id.GREEN, value = g },
              { color_component_id = SwitchColor.color_component_id.BLUE, value = b },
            }
          })
        )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_rgbw_controller,
          SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.RED })
        )
      )
    end
  )
end

do
  local red = math.random(0, 255)
  local green = math.random(0, 255)
  local blue = math.random(0, 255)
  local hue,sat = utils.rgb_to_hsl(red, green, blue)
  test.register_message_test(
    "Z-Wave SwitchColor reports with RGB values should evoke Color Control capability hue and saturation events",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_fibaro_rgbw_controller.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchColor:Report({
              color_component_id=SwitchColor.color_component_id.RED,
              value = red,
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_rgbw_controller:generate_test_message("rgb", capabilities.switch.switch.on())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_fibaro_rgbw_controller.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchColor:Report({
              color_component_id=SwitchColor.color_component_id.GREEN,
              value = green,
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_rgbw_controller:generate_test_message("rgb", capabilities.switch.switch.on())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_fibaro_rgbw_controller.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchColor:Report({
              color_component_id=SwitchColor.color_component_id.BLUE,
              value = blue,
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_rgbw_controller:generate_test_message("rgb", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_rgbw_controller:generate_test_message("rgb", capabilities.colorControl.hue(hue))
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_rgbw_controller:generate_test_message("rgb", capabilities.colorControl.saturation(sat))
      }
    }
  )
end

do
  local warm_white = math.random(1, 255)
  test.register_message_test(
    "Z-Wave SwitchColor reports with warm-white intensities above 0 should indicate that white light is ON",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_fibaro_rgbw_controller.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchColor:Report({
              color_component_id = SwitchColor.color_component_id.WARM_WHITE,
              value = warm_white
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_rgbw_controller:generate_test_message("white", capabilities.switch.switch.on())
      }
    }
  )
end

do
  local warm_white = 0
  test.register_message_test(
    "Z-Wave SwitchColor reports with warm-white intensity equal 0 should indicate that white light is OFF",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_fibaro_rgbw_controller.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchColor:Report({
              color_component_id = SwitchColor.color_component_id.WARM_WHITE,
              value = warm_white
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_rgbw_controller:generate_test_message("white", capabilities.switch.switch.off())
      }
    }
  )
end

test.run_registered_tests()
