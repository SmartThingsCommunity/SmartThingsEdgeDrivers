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

local zw = require "st.zwave"
local test = require "integration_test"
local zw_test_utils = require "integration_test.zwave_test_utils"
local test_utils = require "integration_test.utils"
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2, strict = true })
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1, strict = true })
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4, strict = true })
local Version = (require "st.zwave.CommandClass.Version")({ version = 2 })
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({ version = 1 })
local capabilities = require "st.capabilities"
local constants = require "st.zwave.constants"
local mock_devices_api = require "integration_test.mock_devices_api"

local BUTTON_VALUES = {
  "up_hold", "down_hold", "held",
  "up", "up_2x", "up_3x", "up_4x", "up_5x",
  "down", "down_2x", "down_3x", "down_4x", "down_5x",
  "pushed", "pushed_2x", "pushed_3x", "pushed_4x", "pushed_5x"
}

local zooz_zen_30_dimmer_relay_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.SWITCH_MULTILEVEL },
      { value = zw.CENTRAL_SCENE }
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY }
    }
  }
}

local parent_profile = test_utils.get_profile_definition("zooz-zen-30-dimmer-relay.yml")
local child_profile = test_utils.get_profile_definition("child-switch.yml")

local base_parent = test.mock_device.build_test_zwave_device({
  label = "Zooz Switch",
  profile = parent_profile,
  zwave_endpoints = zooz_zen_30_dimmer_relay_endpoints,
  zwave_manufacturer_id = 0x027A,
  zwave_product_type = 0xA000,
  zwave_product_id = 0xA008
})

local mock_parent = test.mock_device.build_test_zwave_device({
  profile = parent_profile,
  zwave_endpoints = zooz_zen_30_dimmer_relay_endpoints,
  zwave_manufacturer_id = 0x027A,
  zwave_product_type = 0xA000,
  zwave_product_id = 0xA008
})

local mock_child = test.mock_device.build_test_child_device({
  profile = child_profile,
  parent_device_id = mock_parent.id,
  parent_assigned_child_key = string.format("%02X", 1)
})

local function test_init()
  test.mock_device.add_test_device(base_parent)
  test.mock_device.add_test_device(mock_parent)
  test.mock_device.add_test_device(mock_child)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Refresh capability should evoke the correct Z-Wave GETs for parent device",
    function()
      test.socket.zwave:__set_channel_ordering('relaxed')
      test.socket.capability:__queue_receive({
        mock_parent.id,
        { capability = "refresh", component = "main", command = "refresh", args = {} }
      })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchMultilevel:Get({}, { dst_channels = { 0 } })
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Version:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Refresh capability should evoke the correct Z-Wave GETs for child device",
    function()
      test.socket.zwave:__set_channel_ordering('relaxed')
      test.socket.capability:__queue_receive({
        mock_child.id,
        { capability = "refresh", component = "main", command = "refresh", args = {} }
      })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Get({}, { dst_channels = { 1 } })
          )
      )
    end
)

test.register_message_test(
    "Basic Report (0x00) should be handled by child device",
    {
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
    "Basic Report (0x00) should be handled by parent device",
    {
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
    "Basic Report (0xFF) should be handled by child device",
    {
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
    "Basic Report (0xFF) should be handled by parent device",
    {
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
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.switchLevel.level(100))
      }
    }
)

test.register_message_test(
    "Switch Multilevel report ON_ENABLE should be handled by parent device",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchMultilevel:Report({
                current_value = SwitchBinary.value.ON_ENABLE,
                target_value = SwitchBinary.value.ON_ENABLE,
                duration = 0xFF
              }, { src_channel = 0 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.switchLevel.level(100))
      }

    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Switch Multilevel report OFF_DISABLE should be handled by parent device",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchMultilevel:Report({
                target_value = SwitchBinary.value.OFF_DISABLE,
                current_value = SwitchBinary.value.OFF_DISABLE,
                duration = 0xFF
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
    "Switch Binary report ON_ENABLE should be handled by child device",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report({ current_value = SwitchBinary.value.ON_ENABLE, target_value = SwitchBinary.value.ON_ENABLE, duration = 0 }, { src_channel = 1 })
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
    "Switch Binary report OFF_DISABLE should be handled by child device",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report({ current_value = SwitchBinary.value.OFF_DISABLE, target_value = SwitchBinary.value.OFF_DISABLE, duration = 0 }, { src_channel = 1 })
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
    "Switch capability on command should evoke the correct Z-Wave SETs and GETs with dst_channel 0",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_parent.id,
        { capability = "switch", component = "main", command = "on", args = {} }
      })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchMultilevel:Set(
                  { value = SwitchBinary.value.ON_ENABLE, duration = constants.DEFAULT_DIMMING_DURATION },
                  { dst_channels = { 0 } }
              )
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchMultilevel:Get({}, { dst_channels = { 0 } })
          )
      )
    end
)

test.register_coroutine_test(
    "Switch capability off command should evoke the correct Z-Wave SETs and GETs with dst_channel 0",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_parent.id,
        { capability = "switch", component = "main", command = "off", args = {} }
      })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchMultilevel:Set(
                  { value = SwitchBinary.value.OFF_DISABLE, duration = constants.DEFAULT_DIMMING_DURATION },
                  { dst_channels = { 0 } }
              )
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchMultilevel:Get({}, { dst_channels = { 0 } })
          )
      )
    end
)

test.register_coroutine_test(
    "Switch capability on command should evoke the correct Z-Wave SETs and GETs with dst_channel 1",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_child.id,
        { capability = "switch", component = "main", command = "on", args = {} }
      })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Set(
                  { target_value = SwitchBinary.value.ON_ENABLE, duration = 0 },
                  { dst_channels = { 1 } }
              )
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Get({}, { dst_channels = { 1 } })
          )
      )
    end
)

test.register_coroutine_test(
    "Switch capability off command should evoke the correct Z-Wave SETs and GETs with dst_channel 1",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_child.id,
        { capability = "switch", component = "main", command = "off", args = {} }
      })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Set(
                  { target_value = SwitchBinary.value.OFF_DISABLE, duration = 0 },
                  { dst_channels = { 1 } }
              )
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Get({}, { dst_channels = { 1 } })
          )
      )
    end
)

test.register_coroutine_test(
    "SwitchLevel capability setLevel commands should evoke the correct Z-Wave SETs and GETs",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_parent.id,
        { capability = "switchLevel", component = "main", command = "setLevel", args = { 50 } }
      })
      mock_parent:expect_native_cmd_handler_registration("switchLevel", "setLevel")
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchMultilevel:Set({
                value = 50,
                duration = constants.DEFAULT_DIMMING_DURATION
              }, {
                encap = zw.ENCAP.AUTO,
                src_channel = 0,
                dst_channels = { 0 }
              })
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchMultilevel:Get({}, { dst_channels = { 0 } })
          )
      )
    end
)

test.register_message_test(
    "Z-Wave SwitchMultilevel reports with non-zero values should evoke Switch and Switch Level capability events",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchMultilevel:Report({
                current_value = 50,
                target_value = 50,
                duration = 0
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.switchLevel.level(50))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'up' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x01,
                key_attributes = CentralScene.key_attributes.KEY_PRESSED_1_TIME
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.up({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'down' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x02,
                key_attributes = CentralScene.key_attributes.KEY_PRESSED_1_TIME
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.down({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'pushed' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x03,
                key_attributes = CentralScene.key_attributes.KEY_PRESSED_1_TIME
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.pushed({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'up_2x' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x01,
                key_attributes = CentralScene.key_attributes.KEY_PRESSED_2_TIMES
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.up_2x({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'down_2x' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x02,
                key_attributes = CentralScene.key_attributes.KEY_PRESSED_2_TIMES
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.down_2x({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'pushed_2x' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x03,
                key_attributes = CentralScene.key_attributes.KEY_PRESSED_2_TIMES
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.pushed_2x({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'up_3x' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x01,
                key_attributes = CentralScene.key_attributes.KEY_PRESSED_3_TIMES
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.up_3x({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'down_3x' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x02,
                key_attributes = CentralScene.key_attributes.KEY_PRESSED_3_TIMES
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.down_3x({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'pushed_3x' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x03,
                key_attributes = CentralScene.key_attributes.KEY_PRESSED_3_TIMES
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.pushed_3x({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'up_4x' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x01,
                key_attributes = CentralScene.key_attributes.KEY_PRESSED_4_TIMES
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.up_4x({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'down_4x' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x02,
                key_attributes = CentralScene.key_attributes.KEY_PRESSED_4_TIMES
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.down_4x({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'pushed_4x' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x03,
                key_attributes = CentralScene.key_attributes.KEY_PRESSED_4_TIMES
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.pushed_4x({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'up_5x' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x01,
                key_attributes = CentralScene.key_attributes.KEY_PRESSED_5_TIMES
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.up_5x({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'down_5x' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x02,
                key_attributes = CentralScene.key_attributes.KEY_PRESSED_5_TIMES
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.down_5x({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'pushed_5x' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x03,
                key_attributes = CentralScene.key_attributes.KEY_PRESSED_5_TIMES
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.pushed_5x({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'up_hold' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x01,
                key_attributes = CentralScene.key_attributes.KEY_HELD_DOWN
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.up_hold({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'down_hold' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x02,
                key_attributes = CentralScene.key_attributes.KEY_HELD_DOWN
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.down_hold({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'held' should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x03,
                key_attributes = CentralScene.key_attributes.KEY_HELD_DOWN
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.button.button.held({state_change = true}))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button 'released' should not be handled, not supported by SmartThings",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              CentralScene:Notification({
                scene_number = 0x03,
                key_attributes = 0x01
              })
          )
        }
      }
    }
)

test.register_coroutine_test(
    "Profile change when version is changed bigger than 1,5",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zwave:__queue_receive({
        mock_parent.id,
        Version:Report({
          firmware_0_version = 1,
          firmware_0_sub_version = 5
        })
      })

      test.mock_time.advance_time(1)

      test.socket.zwave:__expect_send(
          mock_devices_api.__expect_update_device(
              mock_parent.id, {
                deviceId = mock_parent.id,
                profileReference = "zooz-zen-30-dimmer-relay-new"
              }
          )
      )
    end
)

test.register_coroutine_test(
    "Profile change when version is changed bigger than 1,5",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zwave:__queue_receive({
        mock_parent.id,
        Version:Report({
          firmware_0_version = 2,
          firmware_0_sub_version = 9
        })
      })

      test.mock_time.advance_time(1)

      test.socket.zwave:__expect_send(
          mock_devices_api.__expect_update_device(
              mock_parent.id, {
                deviceId = mock_parent.id,
                profileReference = "zooz-zen-30-dimmer-relay-new"
              }
          )
      )
    end
)

test.register_coroutine_test(
    "New profile do not change when version is bigger than 1,5",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zwave:__queue_receive({
        mock_parent.id,
        Version:Report({
          firmware_0_version = 1,
          firmware_0_sub_version = 6
        })
      })

      test.mock_time.advance_time(1)

      test.socket.zwave:__expect_send(
          mock_devices_api.__expect_update_device(
              mock_parent.id, {
                deviceId = mock_parent.id,
                profileReference = "zooz-zen-30-dimmer-relay-new"
              }
          )
      )

      test.mock_time.advance_time(1)

      test.socket.zwave:__queue_receive({
        mock_parent.id,
        Version:Report({
          firmware_0_version = 1,
          firmware_0_sub_version = 7
        })
      })

    end
)

test.register_coroutine_test(
    "Added lifecycle event should create children for parent device",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ base_parent.id, "added" })
      base_parent:expect_device_create(
          {
            type = "EDGE_CHILD",
            label = "Zooz Switch Relay",
            profile = "child-switch",
            parent_device_id = base_parent.id,
            parent_assigned_child_key = "01"
          }
      )
      test.socket.capability:__expect_send(
          base_parent:generate_test_message(
              "main",
              capabilities.button.supportedButtonValues(BUTTON_VALUES, { visibility = { displayed = false } })
          )
      )
      test.socket.capability:__expect_send(
          base_parent:generate_test_message(
              "main",
              capabilities.button.numberOfButtons({ value = 3 }, { visibility = { displayed = false } })
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              base_parent,
              SwitchMultilevel:Get({},
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 0 } }
              )
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              base_parent,
              Version:Get({},
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {} }
              )
          )
      )
    end
)

test.register_coroutine_test(
    "Added lifecycle event should refresh child device",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_child.id, "added" })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Get({},
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
              )
          )
      )
    end
)

test.run_registered_tests()
