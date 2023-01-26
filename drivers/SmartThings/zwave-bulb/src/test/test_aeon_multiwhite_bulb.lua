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
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local SwitchColor = (require "st.zwave.CommandClass.SwitchColor")({ version = 3 })
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4 })
local constants = require "st.zwave.constants"
local t_utils = require "integration_test.utils"

local WARM_WHITE_CONFIG = 0x51
local COLD_WHITE_CONFIG = 0x52

-- supported comand classes
local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.CONFIGURATION},
      {value = zw.SWITCH_COLOR},
      {value = zw.SWITCH_MULTILEVEL}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("switch-level-colortemp.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x0371,
    zwave_product_type = 0x0103,
    zwave_product_id = 0x0001
})

local function  test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

do
  local level = math.random(1,100)
  test.register_message_test(
    "Basic report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = level }))}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.switchLevel.level({value = level}))
      }
    }
  )
end

test.register_message_test(
  "Check default temperature color set from added handler",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "added" }
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.colorTemperature.colorTemperature(2700))
    -- }
  }
)

test.register_message_test(
  "Basic report should be handled",
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
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switchLevel.level({value = 100}))
    }
  }
)

test.register_message_test(
  "Basic report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0x00 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switchLevel.level({value = 0}))
    }
  }
)

do
  local level = math.random(1,100)
  test.register_message_test(
    "Basic set should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({ value = level }))}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.switchLevel.level({value = level}))
      }
    }
  )
end

test.register_message_test(
  "Basic set should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({ value = 0xFF })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switchLevel.level({value = 100}))
    }
  }
)

test.register_message_test(
  "Basic set should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({ value = 0x00 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switchLevel.level({value = 0}))
    }
  }
)


test.register_message_test(
  "SwitchMultilevel set should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({ value = 0x00 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switchLevel.level({value = 0}))
    }
  }
)


test.register_message_test(
  "SwitchMultilevel set should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({ value = 0xFF })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switchLevel.level({value = 100}))
    }
  }
)

test.register_message_test(
  "SwitchMultilevel set should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({ value = 0x00 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switchLevel.level({value = 0}))
    }
  }
)

do
  local level = math.random(1,100)
  test.register_message_test(
    "SwitchMultilevel report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
          SwitchMultilevel:Report({
            current_value = 0,
            target_value = level,
            duration = 0
          }))
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.switchLevel.level({value = level}))
      }
    }
  )
end

test.register_message_test(
  "SwitchColor report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchColor:Report({
            color_component_id=SwitchColor.color_component_id.COLD_WHITE,
            current_value = 0,
            target_value = 0xFF,
            duration = 0
          })
        )
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Get({parameter_number = 0x52})
      )
    }
  }
)

test.register_message_test(
  "SwitchColor report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchColor:Report({
            color_component_id=SwitchColor.color_component_id.WARM_WHITE,
            current_value = 0,
            target_value = 0xFF,
            duration = 0
          })
        )
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Get({parameter_number = 0x51})
      )
    }
  }
)

do
  local temp = math.random(2700, 6500)
  test.register_message_test(
    "Configuration report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_device.id,
          zw_test_utils.zwave_test_build_receive_command(
            Configuration:Report({
              parameter_number = temp < 5000 and WARM_WHITE_CONFIG or COLD_WHITE_CONFIG,
              configuration_value = temp,
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.colorTemperature.colorTemperature({value = temp}))
      }
    }
  )
end


test.register_coroutine_test(
  "Capability(switch) command(off) on should be handled",
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "switch", component = "main", command = "on", args = { } }})
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
      SwitchMultilevel:Set({ duration = "default", value = 0xFF })
      )
    )
    test.wait_for_events()

    test.mock_time.advance_time(5)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchMultilevel:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Capability(switch) command(off) off should be handled",
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(4, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "switch", component = "main", command = "off", args = { } }})
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchMultilevel:Set({ duration = "default", value = 0x00 })
      )
    )
    test.wait_for_events()

    test.mock_time.advance_time(4)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchMultilevel:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Capability(switchLevel) command(setLevel) on should be handled",
  function ()
    local level = math.random(1,100)
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { level, 10 } }})
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchMultilevel:Set({ value=level, duration = 10 })
      )
    )
    test.wait_for_events()

    test.mock_time.advance_time(12)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchMultilevel:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Color Tempurature capability set commands should evoke Aeotec-specific Z-Wave configuration SETs and GETs",
  function()
    local temp = math.random(2700, 6500)
    local ww = temp < 5000 and 255 or 0
    local cw = temp >= 5000 and 255 or 0
    local parameter_number = temp < 5000 and WARM_WHITE_CONFIG or COLD_WHITE_CONFIG
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.zwave:__queue_receive({
      mock_device.id,
      Basic:Report(
        {
          value = 0xFF
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels = {}
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.switch.switch.on())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.switchLevel.level({value = 100}))
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = "colorTemperature",
        command = "setColorTemperature",
        args = { temp }
      }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Set({
          parameter_number=parameter_number,
          configuration_value=temp
        })
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchColor:Set({
          color_components = {
            { color_component_id = SwitchColor.color_component_id.WARM_WHITE, value = ww },
            { color_component_id = SwitchColor.color_component_id.COLD_WHITE, value = cw }
          }
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.WARM_WHITE })
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.COLD_WHITE })
      )
    )
  end
)

test.run_registered_tests()
