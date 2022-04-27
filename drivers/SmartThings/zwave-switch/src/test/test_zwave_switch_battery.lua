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
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local t_utils = require "integration_test.utils"

-- supported comand classes: SWITCH_BINARY
local switch_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_BINARY},
      {value = zw.BATTERY},
    }
  }
}


local mock_switch = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("switch-vent.yml"),
  zwave_endpoints = switch_endpoints
})

local function test_init()
  test.mock_device.add_test_device(mock_switch)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Battery report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_switch.id, zw_test_utils.zwave_test_build_receive_command(Battery:Report({ battery_level = 0x63 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_switch:generate_test_message("main", capabilities.battery.battery(99))
      }
    }
)

test.register_message_test(
    "Added lifecycle event should be handled",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_switch.id, "added" },
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock_switch,
          SwitchBinary:Get({})
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock_switch,
          Battery:Get({})
        )
      },
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
  "Refresh Capability Command should refresh Switch Binary device",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_switch.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_switch,
        SwitchBinary:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_switch,
        Battery:Get({})
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.run_registered_tests()
