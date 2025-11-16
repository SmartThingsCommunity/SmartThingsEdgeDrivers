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
local Basic = (require "st.zwave.CommandClass.Basic")({version = 1})
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version = 1})
local t_utils = require "integration_test.utils"

-- supported comand classes: BASIC, SWITCH_BINARY, MANUFACTURER_SPECIFIC
local switch_momentary_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.SWITCH_BINARY}
    }
  }
}

local zwave_switch_profile = t_utils.get_profile_definition("switch-momentary.yml")

local mock_momentary_switch = test.mock_device.build_test_zwave_device({
  profile = zwave_switch_profile,
  zwave_endpoints = switch_momentary_endpoints
})

local function test_init()
  test.mock_device.add_test_device(mock_momentary_switch)
end
test.set_test_init_function(test_init)

local zwave_binary_switch_on_report = zw_test_utils.zwave_test_build_receive_command(
  SwitchBinary:Report({value = SwitchBinary.value.ON_ENABLE})
)

local zwave_binary_switch_off_report = zw_test_utils.zwave_test_build_receive_command(
  SwitchBinary:Report({value = SwitchBinary.value.OFF_DISABLE})
)


test.register_message_test(
  "Binary switch on/off report should be handled: on",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_momentary_switch.id, zwave_binary_switch_on_report }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_momentary_switch:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Binary switch on/off report should be handled: off",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_momentary_switch.id, zwave_binary_switch_off_report }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_momentary_switch:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)


test.register_message_test(
  "Refresh Capability Command should refresh Switch Binary device",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_momentary_switch.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_momentary_switch,
        SwitchBinary:Get({})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Refresh commands should be sent after device is added",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_momentary_switch.id, "added" },
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
              mock_momentary_switch,
              SwitchBinary:Get({})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
  "Switch on should generate correct zwave messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_momentary_switch.id,
        { capability = "switch", command = "on", args = {} }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_momentary_switch,
        Basic:Set({
          value = SwitchBinary.value.ON_ENABLE
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_momentary_switch,
        SwitchBinary:Get({})
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(3)

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_momentary_switch,
        Basic:Set({
          value = SwitchBinary.value.OFF_DISABLE
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_momentary_switch,
        SwitchBinary:Get({})
      )
    )
  end
)


test.register_coroutine_test(
  "Momentary push should generate correct zwave messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_momentary_switch.id,
        { capability = "momentary", command = "push", args = {} }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_momentary_switch,
        Basic:Set({
          value = SwitchBinary.value.ON_ENABLE
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_momentary_switch,
        SwitchBinary:Get({})
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(3)

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_momentary_switch,
        Basic:Set({
          value = SwitchBinary.value.OFF_DISABLE
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_momentary_switch,
        SwitchBinary:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Switch off should generate correct zwave messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(constants.DEFAULT_GET_STATUS_DELAY, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_momentary_switch.id,
        { capability = "switch", command = "off", args = {} }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_momentary_switch,
        Basic:Set({
          value=SwitchBinary.value.OFF_DISABLE,
        })
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_momentary_switch,
        SwitchBinary:Get({})
      )
    )
  end
)

test.run_registered_tests()
