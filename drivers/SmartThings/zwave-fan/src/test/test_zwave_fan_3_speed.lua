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
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1, strict=true })
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=4, strict=true })
local SwitchMultilevelV1 = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=1, strict=true })
local fan_speed_helper = (require "zwave_fan_helpers")
local t_utils = require "integration_test.utils"

local fan_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_MULTILEVEL},
      {value = zw.BASIC}
    }
  }
}

--- {mfr = 0x001D, prod = 0x1001, model = 0x0334}, -- Leviton 3-Speed Fan Controller
local mock_fan = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("fan-3speed.yml"),
  zwave_endpoints = fan_endpoints,
  zwave_manufacturer_id = 0x001D,
  zwave_product_type = 0x1001, -- aka product
  zwave_product_id = 0x0334, -- aka model
})

local function test_init()
  test.mock_device.add_test_device(mock_fan)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "3 speed fan SwitchMultiLevelReport should be handled: HIGH",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_fan.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchMultilevel:Report({
              current_value = 0,
              target_value = fan_speed_helper.levels_for_3_speed.MEDIUM + 1, -- 66 + 1
              duration = 0
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fan:generate_test_message("main", capabilities.fanSpeed.fanSpeed({value = fan_speed_helper.fan_speed.HIGH}))
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fan:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)


test.register_message_test(
    "3 speed fan BasicReport should be handled: HIGH",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_fan.id,
          zw_test_utils.zwave_test_build_receive_command(
            Basic:Report({
              value = fan_speed_helper.levels_for_3_speed.MEDIUM + 1 -- 66 + 1
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fan:generate_test_message("main", capabilities.fanSpeed.fanSpeed({value = fan_speed_helper.fan_speed.HIGH}))
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fan:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "3 speed fan SwitchMultiLevelReport should be handled: OFF",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_fan.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchMultilevel:Report({
              current_value = 0,
              target_value = 0,
              duration = 0
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fan:generate_test_message("main", capabilities.fanSpeed.fanSpeed({value = fan_speed_helper.fan_speed.OFF}))
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fan:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "3 speed fan SwitchMultiLevelReportV1 should be handled: HIGH",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_fan.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchMultilevelV1:Report({
              value = fan_speed_helper.levels_for_3_speed.MEDIUM + 1 -- 66 + 1
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fan:generate_test_message("main", capabilities.fanSpeed.fanSpeed({value = fan_speed_helper.fan_speed.HIGH}))
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fan:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_coroutine_test(
    "Setting LOW fan speed shall generate correct Z-Wave commands",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_fan.id,
            { capability = "fanSpeed", command = "setFanSpeed", args = {fan_speed_helper.fan_speed.LOW} } -- low fan spee
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_fan,
              SwitchMultilevel:Set({
                          value=fan_speed_helper.levels_for_3_speed.LOW, -- 33
                          duration = "default"
                        })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_fan,
              SwitchMultilevel:Get({})
          )
      )
    end
)

test.run_registered_tests()
