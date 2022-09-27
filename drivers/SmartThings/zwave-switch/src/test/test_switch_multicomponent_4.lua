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
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2})
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local t_utils = require "integration_test.utils"

local WYFY_MANUFACTURER_ID = 0x015F
local WYFY_PRODUCT_TYPE = 0x3141
local WYFY_PRODUCT_ID = 0x5102

local WYFY_multicomponent_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
    }
  }
}

local mock_switch_multicomponent = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("switch-multicomponent-4.yml"),
  zwave_endpoints = WYFY_multicomponent_endpoints,
  zwave_manufacturer_id = WYFY_MANUFACTURER_ID,
  zwave_product_type = WYFY_PRODUCT_TYPE,
  zwave_product_id = WYFY_PRODUCT_ID
})

local function test_init()
  test.mock_device.add_test_device(mock_switch_multicomponent)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Refresh sends commands to all components including base device",
  function()
    -- refresh commands for zwave devices do not have guaranteed ordering
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_switch_multicomponent,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_switch_multicomponent,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {1}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_switch_multicomponent,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {2}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_switch_multicomponent,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {3}
          })
      ))
    test.socket.capability:__queue_receive({
      mock_switch_multicomponent.id,
      { capability = "refresh", component = "main", command = "refresh", args = { } }
    })
  end
)


test.register_message_test(
  "Multichannel switch on/off capability command on from component 1 should be handled: on",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_switch_multicomponent.id,
        { capability = "switch", command = "on", component = "switch1", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_switch_multicomponent,
        SwitchBinary:Set({ target_value=0xFF },
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1}})
      )
    }
  }
)

test.register_message_test(
  "Multichannel switch on/off capability command off from main component should be handled: off",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_switch_multicomponent.id,
        { capability = "switch", command = "off", component = "main", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_switch_multicomponent,
        SwitchBinary:Set({ target_value=0x00 })
      )
    }
  }
)

test.register_coroutine_test(
  "doConfigure lifecycle event should generate proper configuration commands",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_switch_multicomponent.id, "doConfigure" })
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_switch_multicomponent,
        Configuration:Set({parameter_number = 2, size = 1, configuration_value = 1})
    ))
    mock_switch_multicomponent:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_message_test(
  "Binary switch on/off report from channel 1 should be handled: on",
  {
    {
    channel = "device_lifecycle",
    direction = "receive",
    message = { mock_switch_multicomponent.id, "init" },
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_switch_multicomponent.id,
                  zw_test_utils.zwave_test_build_receive_command(SwitchBinary:Report({ current_value=0xFF },
                  {encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0}}))}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_switch_multicomponent:generate_test_message("switch1", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Z-Wave SwitchBinary reports with value-off should evoke Switch capability off events",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_switch_multicomponent.id, "init" },
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_switch_multicomponent.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report({ current_value=0x00 })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_switch_multicomponent:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

test.register_coroutine_test(
  "Switch capability off commands should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_switch_multicomponent.id,
      { capability = "switch", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_switch_multicomponent,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.OFF_DISABLE
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_switch_multicomponent,
        SwitchBinary:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Switch capability off commands from multicomponent should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_switch_multicomponent.id,
      { capability = "switch", command = "off", component = "switch1", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_switch_multicomponent,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.OFF_DISABLE
        }, { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1} }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_switch_multicomponent,
        SwitchBinary:Get({}, { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {1} })
      )
    )
  end
)

test.run_registered_tests()
