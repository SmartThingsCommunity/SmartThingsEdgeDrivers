---@diagnostic disable: param-type-mismatch, undefined-field
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
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=1})
local t_utils = require "integration_test.utils"

local BASIC_AND_SWITCH_BINARY_REPORT_STROBE_LIMIT = 33
local BASIC_AND_SWITCH_BINARY_REPORT_SIREN_LIMIT = 66
local BASIC_REPORT_SIREN_ACTIVE = 0xFF
local BASIC_REPORT_SIREN_IDLE = 0x00

-- supported comand classes: BASIC
local siren_basic_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC}
    }
  }
}

-- supported comand classes: SWITCH_BINARY
local siren_switch_binary_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_BINARY}
    }
  }
}

local zwave_siren_profile = t_utils.get_profile_definition("base-siren.yml")

local mock_siren_basic = test.mock_device.build_test_zwave_device({
  profile = zwave_siren_profile,
  zwave_endpoints = siren_basic_endpoints
})

local mock_siren_switch_binary = test.mock_device.build_test_zwave_device({
  profile = zwave_siren_profile,
  zwave_endpoints = siren_switch_binary_endpoints
})

local function test_init()
  test.mock_device.add_test_device(mock_siren_basic)
  test.mock_device.add_test_device(mock_siren_switch_binary)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Basic report 0x00 should be handled as alarm off, swtich off",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_siren_basic.id,
          zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = BASIC_REPORT_SIREN_IDLE })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_basic:generate_test_message("main", capabilities.alarm.alarm.off())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_basic:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Basic report value <= 33 should be handled as alarm strobe, swtich on",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_siren_basic.id,
          zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = BASIC_AND_SWITCH_BINARY_REPORT_STROBE_LIMIT })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_basic:generate_test_message("main", capabilities.alarm.alarm.strobe())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_basic:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic report value <= 66 should be handled as alarm siren, swtich on",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_siren_basic.id,
          zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = BASIC_AND_SWITCH_BINARY_REPORT_SIREN_LIMIT })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_basic:generate_test_message("main", capabilities.alarm.alarm.siren())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_basic:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Basic report 0xFF should be handled as alarm both, swtich on",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_siren_basic.id,
          zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = BASIC_REPORT_SIREN_ACTIVE })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_basic:generate_test_message("main", capabilities.alarm.alarm.both())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_basic:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Switch Binary report 0x00 should be handled as alarm off, swtich off",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_siren_switch_binary.id,
          zw_test_utils.zwave_test_build_receive_command(SwitchBinary:Report({value=SwitchBinary.value.OFF_DISABLE})) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_switch_binary:generate_test_message("main", capabilities.alarm.alarm.off())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_switch_binary:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Switch Binary report value <= 33 should be handled as alarm strobe, swtich on",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_siren_switch_binary.id,
          zw_test_utils.zwave_test_build_receive_command(SwitchBinary:Report({value = BASIC_AND_SWITCH_BINARY_REPORT_STROBE_LIMIT})) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_switch_binary:generate_test_message("main", capabilities.alarm.alarm.strobe())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_switch_binary:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Switch Binary report value <= 66 should be handled as alarm siren, swtich on",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_siren_switch_binary.id,
          zw_test_utils.zwave_test_build_receive_command(SwitchBinary:Report({value = BASIC_AND_SWITCH_BINARY_REPORT_SIREN_LIMIT})) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_switch_binary:generate_test_message("main", capabilities.alarm.alarm.siren())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_switch_binary:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Switch Binary report 0xFF should be handled as alarm both, swtich on",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_siren_switch_binary.id,
          zw_test_utils.zwave_test_build_receive_command(SwitchBinary:Report({value=SwitchBinary.value.ON_ENABLE})) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_switch_binary:generate_test_message("main", capabilities.alarm.alarm.both())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_switch_binary:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_coroutine_test(
    "Setting switch on should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_siren_basic.id,
            { capability = "switch", command = "on", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren_basic,
              Basic:Set({value=0xFF})
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren_basic,
              Basic:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting alarm both should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_siren_basic.id,
            { capability = "alarm", command = "both", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren_basic,
              Basic:Set({value=0xFF})
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren_basic,
              Basic:Get({})
          )
      )
    end
)


test.register_coroutine_test(
    "Setting alarm siren should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_siren_basic.id,
            { capability = "alarm", command = "siren", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren_basic,
              Basic:Set({value=0xFF})
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren_basic,
              Basic:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting alarm strobe should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_siren_basic.id,
            { capability = "alarm", command = "strobe", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren_basic,
              Basic:Set({value=0xFF})
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren_basic,
              Basic:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting alarm off should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_siren_basic.id,
            { capability = "alarm", command = "off", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren_basic,
              Basic:Set({value=0x00})
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren_basic,
              Basic:Get({})
          )
      )
    end
)

test.register_coroutine_test(
  "added lifecycle event",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    -- test.socket.capability:__expect_send({
    --   mock_siren_basic.id,
    --   {
    --     capability_id = "alarm", component_id = "main",
    --     attribute_id = "alarm", state = { value = "off" }
    --   }
    -- })
    -- test.socket.capability:__expect_send({
    --   mock_siren_basic.id,
    --   {
    --     capability_id = "battery", component_id = "main"t
    --     attribute_id = "battery", state = { value = 100 }
    --   }
    -- })
    -- test.socket.capability:__expect_send({
    --   mock_siren_basic.id,
    --   {
    --     capability_id = "switch", component_id = "main",
    --     attribute_id = "switch", state = { value = "off" }
    --   }
    -- })
    -- test.socket.capability:__expect_send({
    --   mock_siren_basic.id,
    --   {
    --     capability_id = "tamperAlert", component_id = "main",
    --     attribute_id = "tamper", state = { value = "clear" }
    --   }
    -- })

    test.socket.device_lifecycle:__queue_receive({ mock_siren_basic.id, "added" })
    test.wait_for_events()
    end
)

test.run_registered_tests()
