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
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4 })
local t_utils = require "integration_test.utils"

local inovelli_dimmer_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_MULTILEVEL }
    }
  }
}

local mock_inovelli_dimmer = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("inovelli-dimmer.yml"),
  zwave_endpoints = inovelli_dimmer_endpoints
})

local function test_init()
  test.mock_device.add_test_device(mock_inovelli_dimmer)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Added lifecycle event should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_inovelli_dimmer.id, "added" }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_dimmer,
        SwitchMultilevel:Get({})
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Refresh Capability Command should refresh device",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_inovelli_dimmer.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_dimmer,
        SwitchMultilevel:Get({})
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Z-Wave SwitchMultilevel reports with value-off should evoke Switch capability off events",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_inovelli_dimmer.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchMultilevel:Report({
            target_value = 0,
            current_value = SwitchMultilevel.value.OFF_DISABLE,
            duration = 0
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_dimmer:generate_test_message("main", capabilities.switch.switch.off())
    }
  },
  {
  }
)

do
  local level = 60
  test.register_message_test(
    "Z-Wave SwitchMultilevel reports with non-zero values should evoke Switch and Switch Level capability events",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_inovelli_dimmer.id,
          zw_test_utils.zwave_test_build_receive_command(
            SwitchMultilevel:Report({
              target_value = 0,
              current_value = level,
              duration = 0
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_inovelli_dimmer:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_inovelli_dimmer:generate_test_message("main", capabilities.switchLevel.level(level))
      }
    }
  )
end

test.register_coroutine_test(
  "Switch capability off commands should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_inovelli_dimmer.id,
      { capability = "switch", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_dimmer,
        SwitchMultilevel:Set({
          value = SwitchMultilevel.value.OFF_DISABLE,
          duration = constants.DEFAULT_DIMMING_DURATION
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_dimmer,
        SwitchMultilevel:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Switch capability on commands should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_inovelli_dimmer.id,
      { capability = "switch", command = "on", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_dimmer,
        SwitchMultilevel:Set({
          value = SwitchMultilevel.value.ON_ENABLE,
          duration = constants.DEFAULT_DIMMING_DURATION
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_dimmer,
        SwitchMultilevel:Get({})
      )
    )
  end
)

do
  local level = 49
  test.register_coroutine_test(
    "SwitchLevel capability setLevel commands should evoke the correct Z-Wave SETs and GETs",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_inovelli_dimmer.id,
        { capability = "switchLevel", command = "setLevel", args = { level } }
      })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_inovelli_dimmer,
          SwitchMultilevel:Set({
            value = level,
            duration = constants.DEFAULT_DIMMING_DURATION
          })
        )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_inovelli_dimmer,
          SwitchMultilevel:Get({})
        )
      )
    end
  )
end

test.run_registered_tests()
