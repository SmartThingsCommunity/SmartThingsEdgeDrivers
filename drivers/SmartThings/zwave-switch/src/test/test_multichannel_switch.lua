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
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2, strict = true })
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({version=4,strict=true})
local t_utils = require "integration_test.utils"

-- supported command classes
local switch_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.MULTI_CHANNEL }
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.MULTI_CHANNEL }
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.MULTI_CHANNEL }
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.SWITCH_MULTILEVEL },
      { value = zw.MULTI_CHANNEL }
    }
  }
}

local mock_parent = test.mock_device.build_test_zwave_device({
  label = "Z-Wave Switch Multichannel",
  profile = t_utils.get_profile_definition("multichannel-switch-binary.yml"),
  zwave_endpoints = switch_endpoints
})

local mock_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("multichannel-switch-binary.yml"),
  parent_device_id = mock_parent.id,
  parent_assigned_child_key = string.format("%02X", 1)
})

local mock_child_2 = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("multichannel-switch-binary.yml"),
  parent_device_id = mock_parent.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

local mock_child_3 = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("multichannel-switch-level.yml"),
  parent_device_id = mock_parent.id,
  parent_assigned_child_key = string.format("%02X", 3)
})

local function test_init()
  test.mock_device.add_test_device(mock_parent)
  test.mock_device.add_test_device(mock_child)
  test.mock_device.add_test_device(mock_child_2)
  test.mock_device.add_test_device(mock_child_3)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Basic report (0x00) should be handled by parent device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x00 }, { src_channel = 0 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Basic report (0x00) should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x00 }, { src_channel = 1 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Basic report (0x00) should be handled by child 2 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x00 }, { src_channel = 2 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Basic report (0x00) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x00 }, { src_channel = 3 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Basic report (0xFF) should be handled by parent device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0xFF }, { src_channel = 0 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic report (0xFF) should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0xFF }, { src_channel = 1 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic report (0xFF) should be handled by child 2 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0xFF }, { src_channel = 2 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic report (0xFF) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0xFF }, { src_channel = 3 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switchLevel.level(100))
      }
    }
)

test.register_message_test(
    "Basic report (0x32) should be handled by parent device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x32 }, { src_channel = 0 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic report (0x32) should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x32 }, { src_channel = 1 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic report (0x32) should be handled by child 2 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x32 }, { src_channel = 2 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic report (0x32) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x32 }, { src_channel = 3 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switchLevel.level(50))
      }
    }
)

test.register_message_test(
    "SwitchBinary report (OFF_DISABLE) should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report({
                current_value = SwitchBinary.value.OFF_DISABLE,
                target_value = SwitchBinary.value.OFF_DISABLE,
                duration = 0
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "SwitchBinary report (OFF_DISABLE) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report({
                current_value = SwitchBinary.value.OFF_DISABLE,
                target_value = SwitchBinary.value.OFF_DISABLE,
                duration = 0
              }, {
                src_channel = 3
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "SwitchBinary report (ON_ENABLE) should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report({
                current_value = SwitchBinary.value.ON_ENABLE,
                target_value = SwitchBinary.value.ON_ENABLE,
                duration = 0
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "SwitchBinary report (ON_ENABLE) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report({
                current_value = SwitchBinary.value.ON_ENABLE,
                target_value = SwitchBinary.value.ON_ENABLE,
                duration = 0
              }, {
                src_channel = 3
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "SwitchMultilevel report (ON_ENABLE) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchMultilevel:Report({
                current_value = SwitchBinary.value.ON_ENABLE,
                target_value = SwitchBinary.value.ON_ENABLE,
                duration = 0
              }, {
                src_channel = 3
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switchLevel.level(100))
      }
    }
)

test.register_message_test(
    "SwitchMultilevel report (OFF_DISABLE) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchMultilevel:Report({
                current_value = SwitchBinary.value.OFF_DISABLE,
                target_value = SwitchBinary.value.OFF_DISABLE,
                duration = 0
              }, {
                src_channel = 3
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "SwitchMultilevel report (0x32) should be handled by child 3 device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchMultilevel:Report({
                current_value = 50,
                target_value = 0,
                duration = 0
              }, {
                src_channel = 3
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3:generate_test_message("main", capabilities.switchLevel.level(50))
      }
    }
)

test.run_registered_tests()