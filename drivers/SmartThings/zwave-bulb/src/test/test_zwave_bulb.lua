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
local color_utils = require "st.zwave.utils.color"
local constants = require "st.zwave.constants"
local utils = require "st.utils"
local zw_test_utils = require "integration_test.zwave_test_utils"
local cc = require "st.zwave.CommandClass"
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=4 })
local SwitchColor = (require "st.zwave.CommandClass.SwitchColor")({ version=3 })
local t_utils = require "integration_test.utils"

-- supported comand classes
local zwave_bulb_endpoints = {
  {
    command_classes = {
      {value = cc.SWITCH_MULTILEVEL},
      {value = cc.SWITCH_COLOR}
    }
  }
}

local mock_zwave_bulb = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("rgbw-bulb.yml"),
  zwave_endpoints = zwave_bulb_endpoints
})

local function test_init()
  test.mock_device.add_test_device(mock_zwave_bulb)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Refresh capability refresh commands should evoke Z-Wave GETs to bootstrap state",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_zwave_bulb.id, "added" }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_zwave_bulb.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zwave_bulb,
        SwitchMultilevel:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zwave_bulb,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.RED })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zwave_bulb,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.GREEN })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zwave_bulb,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.BLUE })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zwave_bulb,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.WARM_WHITE })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zwave_bulb,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.COLD_WHITE })
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
  "Switch capability off commands should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_zwave_bulb.id,
      { capability = "switch", command = "off", args = {} }
    })
    mock_zwave_bulb:expect_native_cmd_handler_registration("switch", "off")

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zwave_bulb,
        SwitchMultilevel:Set({
          value = SwitchMultilevel.value.OFF_DISABLE,
          duration = constants.DEFAULT_DIMMING_DURATION
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zwave_bulb,
        SwitchMultilevel:Get({})
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
        mock_zwave_bulb.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchMultilevel:Report({
            current_value = 0,
            target_value = SwitchMultilevel.value.OFF_DISABLE,
            duration = 0
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zwave_bulb:generate_test_message("main", capabilities.switch.switch.off())
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
      mock_zwave_bulb.id,
      { capability = "switchLevel", command = "setLevel", args = { level } }
    })
    mock_zwave_bulb:expect_native_cmd_handler_registration("switchLevel", "setLevel")

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zwave_bulb,
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
        mock_zwave_bulb,
          SwitchMultilevel:Get({})
      )
    )
  end,
  {
  }
)

test.register_coroutine_test(
  "Switch capability on commands should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_zwave_bulb.id,
      { capability = "switch", command = "on", args = {} }
    })
    mock_zwave_bulb:expect_native_cmd_handler_registration("switch", "on")

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zwave_bulb,
        SwitchMultilevel:Set({
          value = SwitchMultilevel.value.ON_ENABLE,
          duration = constants.DEFAULT_DIMMING_DURATION
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zwave_bulb,
        SwitchMultilevel:Get({})
      )
    )
  end,
  {
  }
)

do
  local level = math.random(1,100)
  test.register_message_test(
    "Z-Wave SwitchMultilevel reports with non-zero values should evoke Switch and Switch Level capability events",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_zwave_bulb.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchMultilevel:Report({
              target_value = 0,
              current_value = level,
              duration = 0
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_zwave_bulb:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_zwave_bulb:generate_test_message("main", capabilities.switchLevel.level(level))
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
        mock_zwave_bulb.id,
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
          mock_zwave_bulb,
          SwitchColor:Set({
            color_components = {
              { color_component_id = SwitchColor.color_component_id.RED, value = r },
              { color_component_id = SwitchColor.color_component_id.GREEN, value = g },
              { color_component_id = SwitchColor.color_component_id.BLUE, value = b },
              { color_component_id = SwitchColor.color_component_id.WARM_WHITE, value = 0 },
              { color_component_id = SwitchColor.color_component_id.COLD_WHITE, value = 0 },
            },
            duration = constants.DEFAULT_DIMMING_DURATION
          })
        )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_zwave_bulb,
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
          mock_zwave_bulb.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchColor:Report({
              color_component_id=SwitchColor.color_component_id.RED,
              current_value = 0,
              target_value = red,
              duration = 0
            })
          )
        }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_zwave_bulb.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchColor:Report({
              color_component_id=SwitchColor.color_component_id.GREEN,
              current_value = 0,
              target_value = green,
              duration = 0
            })
          )
        }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_zwave_bulb.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchColor:Report({
              color_component_id=SwitchColor.color_component_id.BLUE,
              current_value = blue,
              target_value = blue,
              duration = 0
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_zwave_bulb:generate_test_message("main", capabilities.colorControl.hue(hue))
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_zwave_bulb:generate_test_message("main", capabilities.colorControl.saturation(sat))
      }
    }
  )
end

test.register_coroutine_test(
  "Color Temperature capability setColorTemperature commands should evoke the correct Z-Wave SETs and GETs",
  function()
    local temp = math.random(2700, 6500)
    local warm_white, cold_white = color_utils.temp2White(temp)
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_zwave_bulb.id,
      {
        capability = "colorTemperature",
        command = "setColorTemperature",
        args = { temp }
      }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zwave_bulb,
        SwitchColor:Set({
          color_components = {
            { color_component_id = SwitchColor.color_component_id.RED, value = 0 },
            { color_component_id = SwitchColor.color_component_id.GREEN, value = 0 },
            { color_component_id = SwitchColor.color_component_id.BLUE, value = 0 },
            { color_component_id = SwitchColor.color_component_id.WARM_WHITE, value = warm_white },
            { color_component_id = SwitchColor.color_component_id.COLD_WHITE, value = cold_white },
          },
          duration = constants.DEFAULT_DIMMING_DURATION
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zwave_bulb,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.WARM_WHITE })
      )
    )
  end
)

do
  local warm_white = math.random(0, 255)
  local cold_white = math.random(0, 255)
  local temp = color_utils.white2Temp(warm_white, cold_white)
  test.register_message_test(
    "Z-Wave SwitchColor reports with warm-white and cold-white intensities should evoke Color Temperature capability colorTemperature events",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_zwave_bulb.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchColor:Report({
              color_component_id = SwitchColor.color_component_id.WARM_WHITE,
              current_value = 0,
              target_value = warm_white,
              duration = 0
            })
          )
        }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_zwave_bulb.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchColor:Report({
              color_component_id=SwitchColor.color_component_id.COLD_WHITE,
              current_value = 0,
              target_value = cold_white,
              duration = 0
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_zwave_bulb:generate_test_message("main", capabilities.colorTemperature.colorTemperature(temp))
      }
    }
  )
end

test.run_registered_tests()
