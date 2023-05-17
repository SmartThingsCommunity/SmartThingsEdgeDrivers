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
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
local t_utils = require "integration_test.utils"

-- supported comand classes
local sensor_endpoints = {
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.SWITCH_BINARY}
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.SWITCH_BINARY}
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.SWITCH_BINARY}
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.SWITCH_BINARY}
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.SWITCH_BINARY}
  }},
  {command_classes = {
    {value = zw.BASIC},
    {value = zw.SWITCH_BINARY}
  }}
}

local mock_device = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("switch-5.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x015D,
    zwave_product_type = 0x0651,
    zwave_product_id = 0xF51C
})

local function  test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Basic report (0xFF) should be handled by switch1 componet",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report({value=0xFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 1,
            dst_channels = { 0 }
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch1", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Basic report (0xFF) should be handled by switch2 componet",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report({value=0xFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 2,
            dst_channels = { 0 }
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch2", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Basic report (0xFF) should be handled by switch3 componet",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report({value=0xFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 3,
            dst_channels = { 0 }
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch3", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Basic report (0xFF) should be handled by switch4 componet",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report({value=0xFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 4,
            dst_channels = { 0 }
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch4", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Basic report (0xFF) should be handled by switch5 componet",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report({value=0xFF},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 5,
            dst_channels = { 0 }
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch5", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Basic report (0x00) should be handled by switch1 componet",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report({value=0x00},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 1,
            dst_channels = { 0 }
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch1", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

test.register_message_test(
  "Basic report (0x00) should be handled by switch2 componet",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report({value=0x00},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 2,
            dst_channels = { 0 }
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch2", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)


test.register_message_test(
  "Basic report (0x00) should be handled by switch3 componet",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report({value=0x00},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 3,
            dst_channels = { 0 }
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch3", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)


test.register_message_test(
  "Basic report (0x00) should be handled by switch4 componet",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report({value=0x00},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 4,
            dst_channels = { 0 }
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch4", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)


test.register_message_test(
  "Basic report (0x00) should be handled by switch5 componet",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report({value=0x00},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 5,
            dst_channels = { 0 }
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch5", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)


test.register_message_test(
  "Switch Binary report ON_ENABLE should be handled by switch1 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            {
              current_value=SwitchBinary.value.ON_ENABLE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 1,
              dst_channels={0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch1", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Switch Binary report ON_ENABLE should be handled by switch2 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            {
              current_value=SwitchBinary.value.ON_ENABLE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels={0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch2", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Switch Binary report ON_ENABLE should be handled by switch3 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            {
              current_value=SwitchBinary.value.ON_ENABLE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 3,
              dst_channels={0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch3", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Switch Binary report ON_ENABLE should be handled by switch4 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            {
              current_value=SwitchBinary.value.ON_ENABLE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 4,
              dst_channels={0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch4", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Switch Binary report ON_ENABLE should be handled by switch5 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            {
              current_value=SwitchBinary.value.ON_ENABLE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 5,
              dst_channels={0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch5", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Switch Binary report OFF_DISABLE should be handled by switch1 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            {
              current_value=SwitchBinary.value.OFF_DISABLE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 1,
              dst_channels={0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch1", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

test.register_message_test(
  "Switch Binary report OFF_DISABLE should be handled by switch2 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            {
              current_value=SwitchBinary.value.OFF_DISABLE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels={0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch2", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

test.register_message_test(
  "Switch Binary report OFF_DISABLE should be handled by switch3 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            {
              current_value=SwitchBinary.value.OFF_DISABLE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 3,
              dst_channels={0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch3", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

test.register_message_test(
  "Switch Binary report OFF_DISABLE should be handled by switch4 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            {
              current_value=SwitchBinary.value.OFF_DISABLE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 4,
              dst_channels={0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch4", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

test.register_message_test(
  "Switch Binary report OFF_DISABLE should be handled by switch5 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            {
              current_value=SwitchBinary.value.OFF_DISABLE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 5,
              dst_channels={0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch5", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

test.register_coroutine_test(
  "When all component is off, main switch should be off",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zwave:__queue_receive({
      mock_device.id,
        SwitchBinary:Report({
          current_value = SwitchBinary.value.ON_ENABLE,
          duration = 0
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 1,
          dst_channels={0}
        })
      }
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("switch1", capabilities.switch.switch.on()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switch.switch.on()))
    test.wait_for_events()
    test.mock_time.advance_time(1)

    for i = 2,5 do
      test.socket.zwave:__queue_receive({
        mock_device.id,
          SwitchBinary:Report({
            current_value = SwitchBinary.value.OFF_DISABLE,
            duration = 0
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = i,
            dst_channels={0}
          })
        }
      )
      test.socket.capability:__expect_send(mock_device:generate_test_message("switch"..i, capabilities.switch.switch.off()))
    end
    test.wait_for_events()
    test.mock_time.advance_time(1)

    test.socket.zwave:__queue_receive({
      mock_device.id,
        SwitchBinary:Report({
          current_value = SwitchBinary.value.OFF_DISABLE,
          duration = 0
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 1,
          dst_channels={0}
        })
      }
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("switch1", capabilities.switch.switch.off()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switch.switch.off()))
  end
)

test.register_message_test(
  "When main component is on, should generate proper multi channel messages",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", command = "on", component = "main", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set(
          { target_value=SwitchBinary.value.ON_ENABLE, duration = 0 },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1, 2, 3, 4, 5}}
        )
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {3}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {5}})
      )
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "When main component is off, should generate proper multi channel messages",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", command = "off", component = "main", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set(
          { target_value=SwitchBinary.value.OFF_DISABLE, duration = 0 },
          { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1, 2, 3, 4, 5}}
        )
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {3}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {5}})
      )
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Switch on for component 1, should generate proper zwave commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", command = "on", component = "switch1", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({ target_value=SwitchBinary.value.ON_ENABLE },
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1}})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Switch off for component 1, should generate proper zwave commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", command = "off", component = "switch1", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({ target_value=SwitchBinary.value.OFF_DISABLE },
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1}})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Switch on for component 2, should generate proper zwave commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", command = "on", component = "switch2", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({ target_value=SwitchBinary.value.ON_ENABLE },
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Switch off for component 2, should generate proper zwave commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", command = "off", component = "switch2", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({ target_value=SwitchBinary.value.OFF_DISABLE },
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Switch on for component 3, should generate proper zwave commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", command = "on", component = "switch3", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({ target_value=SwitchBinary.value.ON_ENABLE },
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {3}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {3}})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Switch off for component 3, should generate proper zwave commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", command = "off", component = "switch3", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({ target_value=SwitchBinary.value.OFF_DISABLE },
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {3}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {3}})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Switch on for component 4, should generate proper zwave commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", command = "on", component = "switch4", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({ target_value=SwitchBinary.value.ON_ENABLE },
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Switch off for component 4, should generate proper zwave commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", command = "off", component = "switch4", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({ target_value=SwitchBinary.value.OFF_DISABLE },
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Switch on for component 5, should generate proper zwave commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", command = "on", component = "switch5", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({ target_value=SwitchBinary.value.ON_ENABLE },
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {5}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {5}})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Switch off for component 5, should generate proper zwave commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", command = "off", component = "switch5", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({ target_value=SwitchBinary.value.OFF_DISABLE },
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {5}})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {5}})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.run_registered_tests()
