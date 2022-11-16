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
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4 })
local t_utils = require "integration_test.utils"

-- supported comand classes
local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.SWITCH_BINARY},
      {value = zw.SWITCH_MULTILEVEL}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("switch-level.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x001A,
    zwave_product_type = 0x4441,
    zwave_product_id = 0x0000
})

local function  test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Basic report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0xFF })) }
    }
  }
)

test.register_message_test(
  "Basic set should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({ value = 0x00 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switchLevel.level(0))
    }
  }
)

test.register_message_test(
  "SwitchBinary report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SwitchBinary:Report({ current_value=SwitchBinary.value.OFF_DISABLE })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

do
  local level = math.random(1,100)
  test.register_message_test(
    "Z-Wave SwitchMultilevel reports with non-zero values should evoke Switch and Switch Level capability events",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_device.id,
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
        message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.switchLevel.level(level))
      }
    }
  )
end

do
local level = math.random(1,100)
test.register_message_test(
  "SwitchMultilevel set should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SwitchMultilevel:Set({ value = level })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switchLevel.level(level))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SwitchMultilevel:StopLevelChange({})) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchMultilevel:Get({})
      )
    }
  }
)
end

test.register_coroutine_test(
  "Capability(switch) command(off) on should be handled",
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "switch", component = "main", command = "on", args = { } }})
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Basic:Set({ value = 0xFF })
      )
    )
    test.wait_for_events()

    test.mock_time.advance_time(4)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchMultilevel:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Capability(switch) command(off) on should be handled",
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "switch", component = "main", command = "off", args = { } }})
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Basic:Set({ value = 0x00 })
      )
    )
    test.wait_for_events()

    test.mock_time.advance_time(4)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchMultilevel:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Capability(switchLevel) command(setLevel) on should be handled",
  function ()
    local level = math.random(1,100)
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { level, 10 } }})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switch.switch.on()))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchMultilevel:Set({ value=level, duration = 10 })
      )
    )
    test.wait_for_events()

    test.mock_time.advance_time(5)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchMultilevel:Get({})
      )
    )
  end
)

test.run_registered_tests()
