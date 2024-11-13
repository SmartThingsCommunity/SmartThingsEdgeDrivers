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
local t_utils = require "integration_test.utils"

-- supported comand classes
local switch_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY }
    },
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY }
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY }
    }
  }
}

local mock_parent = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("switch-binary.yml"),
  zwave_endpoints = switch_endpoints,
  zwave_manufacturer_id = 0x0086,
  zwave_product_type = 0x0103,
  zwave_product_id = 0x008C
})

local mock_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("switch-binary.yml"),
  parent_device_id = mock_parent.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

local function test_init()
  test.mock_device.add_test_device(mock_parent)
  test.mock_device.add_test_device(mock_child)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Basic Set (0xFF) should be handled by parent device",
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
              Basic:Set({ value = 0xFF },
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
        message = mock_parent:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic Set (0xFF) should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_child.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Set({ value = 0xFF },
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
        message = mock_child:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic Set (0x00) should be handled by parent device",
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
              Basic:Set({ value = 0x00 },
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
        message = mock_parent:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Basic Set (0x00) should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_child.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Set({ value = 0x00 },
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
        message = mock_child:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Basic Report (0xFF) should be handled by parent device",
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
              Basic:Report({ value = 0xFF },
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
        message = mock_parent:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic Report (0xFF) should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_child.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0xFF },
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
        message = mock_child:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic Report (0x00) should be handled by parent device",
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
              Basic:Report({ value = 0x00 },
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
        message = mock_parent:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Basic Report (0x00) should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_child.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({ value = 0x00 },
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
        message = mock_child:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Switch Binary Report ON_ENABLE should be handled by parent device",
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
              SwitchBinary:Report(
                  {
                    target_value = SwitchBinary.value.ON_ENABLE,
                    current_value = SwitchBinary.value.ON_ENABLE,
                    duration = 0
                  },
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 1,
                    dst_channels = { 0 }
                  }
              )
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
    "Switch Binary Report ON_ENABLE should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_child.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report(
                  {
                    target_value = SwitchBinary.value.ON_ENABLE,
                    current_value = SwitchBinary.value.ON_ENABLE,
                    duration = 0
                  },
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 2,
                    dst_channels = { 0 }
                  }
              )
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
    "Switch Binary Report OFF_DISABLE should be handled by parent device",
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
              SwitchBinary:Report(
                  {
                    target_value = SwitchBinary.value.OFF_DISABLE,
                    current_value = SwitchBinary.value.OFF_DISABLE,
                    duration = 0
                  },
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 1,
                    dst_channels = { 0 }
                  }
              )
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
    "Switch Binary Report OFF_DISABLE should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_child.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report(
                  {
                    target_value = SwitchBinary.value.OFF_DISABLE,
                    current_value = SwitchBinary.value.OFF_DISABLE,
                    duration = 0
                  },
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 2,
                    dst_channels = { 0 }
                  }
              )
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

test.register_coroutine_test(
    "Switch capability on commands should evoke the correct Z-Wave SETs and GETs with dest_channel 1",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_parent.id,
        { capability = "switch", component = "main", command = "on", args = {} }
      })

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Set({
                target_value = SwitchBinary.value.ON_ENABLE,
                duration = 0
              }, {
                encap = zw.ENCAP.AUTO,
                src_channel = 0,
                dst_channels = { 1 }
              })
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Get({}, {
                encap = zw.ENCAP.AUTO,
                src_channel = 0,
                dst_channels = { 1 }
              })
          )
      )
    end
)

test.register_coroutine_test(
    "Switch capability on commands should evoke the correct Z-Wave SETs and GETs with dest_channel 2",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_child.id,
        { capability = "switch", component = "main", command = "on", args = {} }
      })

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Set({
                target_value = SwitchBinary.value.ON_ENABLE,
                duration = 0
              }, {
                encap = zw.ENCAP.AUTO,
                src_channel = 0,
                dst_channels = { 2 }
              })
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Get({}, {
                encap = zw.ENCAP.AUTO,
                src_channel = 0,
                dst_channels = { 2 }
              })
          )
      )
    end
)

test.register_coroutine_test(
    "Switch capability off commands should evoke the correct Z-Wave SETs and GETs dest_channel 1",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_parent.id,
        { capability = "switch", component = "main", command = "off", args = {} }
      })

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Set({
                target_value = SwitchBinary.value.OFF_DISABLE,
                duration = 0
              }, {
                encap = zw.ENCAP.AUTO,
                src_channel = 0,
                dst_channels = { 1 }
              })
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Get({}, {
                encap = zw.ENCAP.AUTO,
                src_channel = 0,
                dst_channels = { 1 }
              })
          )
      )
    end
)

test.register_coroutine_test(
    "Switch capability off commands should evoke the correct Z-Wave SETs and GETs with dest_channel 2",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_child.id,
        { capability = "switch", component = "main", command = "off", args = {} }
      })

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Set({
                target_value = SwitchBinary.value.OFF_DISABLE,
                duration = 0
              }, {
                encap = zw.ENCAP.AUTO,
                src_channel = 0,
                dst_channels = { 2 }
              })
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Get({}, {
                encap = zw.ENCAP.AUTO,
                src_channel = 0,
                dst_channels = { 2 }
              })
          )
      )
    end
)

test.register_coroutine_test(
    "Refresh capability (parent) should evoke the correct Z-Wave GETs",
    function()
      test.socket.zwave:__set_channel_ordering('relaxed')
      test.socket.capability:__queue_receive({
        mock_parent.id,
        { capability = "refresh", component = "main", command = "refresh", args = {} }
      })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Get({}, {
                encap = zw.ENCAP.AUTO,
                src_channel = 0,
                dst_channels = { 1 }
              })
          )
      )
    end
)

test.register_coroutine_test(
    "Refresh capability (child) should evoke the correct Z-Wave GETs",
    function()
      test.socket.zwave:__set_channel_ordering('relaxed')
      test.socket.capability:__queue_receive({
        mock_child.id,
        { capability = "refresh", component = "main", command = "refresh", args = {} }
      })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Get({}, {
                encap = zw.ENCAP.AUTO,
                src_channel = 0,
                dst_channels = { 2 }
              })
          )
      )
    end
)

test.run_registered_tests()
