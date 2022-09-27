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
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=4 })
local t_utils = require "integration_test.utils"

-- supported comand classes: BASIC
local window_shade_basic_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC}
    }
  }
}

-- supported comand classes: SWITCH_MULTILEVEL
local window_shade_switch_multilevel_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_MULTILEVEL}
    }
  }
}

local zwave_window_shade_profile = t_utils.get_profile_definition("base-window-treatment.yml")

local mock_window_shade_basic = test.mock_device.build_test_zwave_device({
  profile = zwave_window_shade_profile,
  zwave_endpoints = window_shade_basic_endpoints
})

local mock_window_shade_switch_multilevel = test.mock_device.build_test_zwave_device({
  profile = zwave_window_shade_profile,
  zwave_endpoints = window_shade_switch_multilevel_endpoints
})

local function test_init()
  test.mock_device.add_test_device(mock_window_shade_basic)
  test.mock_device.add_test_device(mock_window_shade_switch_multilevel)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Basic report 0 should be handled as window shade closed",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_window_shade_basic.id,
          zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_window_shade_basic:generate_test_message("main", capabilities.windowShade.windowShade.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_window_shade_basic:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
      }
    }
)

test.register_message_test(
    "Basic report 1 ~ 98 should be handled as window shade partially open",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_window_shade_basic.id,
          zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 50 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_window_shade_basic:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_window_shade_basic:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50))
      }
    }
)

test.register_message_test(
    "Basic report 99 should be handled as window shade open",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_window_shade_basic.id,
          zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 99 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_window_shade_basic:generate_test_message("main", capabilities.windowShade.windowShade.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_window_shade_basic:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
      }
    }
)

test.register_message_test(
  "Switch multilevel report 0 should be handled as window shade closed",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_window_shade_switch_multilevel.id,
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
      message = mock_window_shade_switch_multilevel:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_window_shade_switch_multilevel:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
    }
  }
)

test.register_message_test(
  "Switch multilevel report 1 ~ 98 should be handled as window shade partially open",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_window_shade_switch_multilevel.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchMultilevel:Report({
            target_value = 0,
            current_value = 50,
            duration = 0
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_window_shade_switch_multilevel:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_window_shade_switch_multilevel:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50))
    }
  }
)

test.register_message_test(
  "Switch multilevel report 99 should be handled as window shade open",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_window_shade_switch_multilevel.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchMultilevel:Report({
            target_value = 0,
            current_value = 99,
            duration = 0
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_window_shade_switch_multilevel:generate_test_message("main", capabilities.windowShade.windowShade.open())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_window_shade_switch_multilevel:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
    }
  }
)

test.register_coroutine_test(
    "Setting window shade open should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_window_shade_switch_multilevel.id,
            { capability = "windowShade", command = "open", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_window_shade_switch_multilevel,
            SwitchMultilevel:Set({
              value = 99,
              duration = constants.DEFAULT_DIMMING_DURATION
            })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_window_shade_switch_multilevel,
            SwitchMultilevel:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting window shade close should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_window_shade_switch_multilevel.id,
            { capability = "windowShade", command = "close", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_window_shade_switch_multilevel,
              SwitchMultilevel:Set({
              value = SwitchMultilevel.value.OFF_DISABLE,
              duration = constants.DEFAULT_DIMMING_DURATION
            })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_window_shade_switch_multilevel,
            SwitchMultilevel:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting window shade pause should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_window_shade_switch_multilevel.id,
            { capability = "windowShade", command = "pause", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_window_shade_switch_multilevel,
            SwitchMultilevel:StopLevelChange({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting window shade preset generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_window_shade_switch_multilevel.id,
            { capability = "windowShadePreset", command = "presetPosition", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_window_shade_switch_multilevel,
            SwitchMultilevel:Set({
              value = 50,
              duration = constants.DEFAULT_DIMMING_DURATION
            })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_window_shade_switch_multilevel,
            SwitchMultilevel:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting window shade level generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_window_shade_switch_multilevel.id,
            { capability = "windowShadeLevel", command = "setShadeLevel", args = { 33 }}
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_window_shade_switch_multilevel,
            SwitchMultilevel:Set({
              value = 33,
              duration = constants.DEFAULT_DIMMING_DURATION
            })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_window_shade_switch_multilevel,
            SwitchMultilevel:Get({})
          )
      )
    end
)

test.register_coroutine_test(
  "Switch multilevel report 0 should be handled as window shade open when reverse preference is set",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.device_lifecycle():__queue_receive(mock_window_shade_switch_multilevel:generate_info_changed(
      {
          preferences = {
            reverse = true
          }
      }
    ))
    test.wait_for_events()
    test.socket.zwave:__queue_receive({
      mock_window_shade_switch_multilevel.id,
        SwitchMultilevel:Report({
          current_value = SwitchMultilevel.value.OFF_DISABLE,
          target_value = SwitchMultilevel.value.OFF_DISABLE,
          duration = 0
        })
      }
    )
    test.socket.capability:__expect_send(mock_window_shade_switch_multilevel:generate_test_message("main", capabilities.windowShade.windowShade.open()))
    test.socket.capability:__expect_send(mock_window_shade_switch_multilevel:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100)))
  end
)

test.register_coroutine_test(
  "Switch multilevel report 0xFF should be handled as window shade close when reverse preference is set",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.device_lifecycle():__queue_receive(mock_window_shade_switch_multilevel:generate_info_changed(
      {
          preferences = {
            reverse = true
          }
      }
    ))
    test.wait_for_events()
    test.socket.zwave:__queue_receive({
      mock_window_shade_switch_multilevel.id,
        SwitchMultilevel:Report({
          current_value = SwitchMultilevel.value.ON_ENABLE,
          target_value = SwitchMultilevel.value.ON_ENABLE,
          duration = 0
        })
      }
    )
    test.socket.capability:__expect_send(mock_window_shade_switch_multilevel:generate_test_message("main", capabilities.windowShade.windowShade.closed()))
    test.socket.capability:__expect_send(mock_window_shade_switch_multilevel:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0)))
  end
)

test.register_coroutine_test(
    "Setting window shade open should generate correct zwave messages when reverse preference is set",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.device_lifecycle():__queue_receive(mock_window_shade_switch_multilevel:generate_info_changed(
        {
            preferences = {
              reverse = true
            }
        }
      ))
      test.wait_for_events()
      test.socket.capability:__queue_receive(
          {
            mock_window_shade_switch_multilevel.id,
            { capability = "windowShade", command = "open", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_window_shade_switch_multilevel,
            SwitchMultilevel:Set({
              value = 0,
              duration = constants.DEFAULT_DIMMING_DURATION
            })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_window_shade_switch_multilevel,
            SwitchMultilevel:Get({})
          )
      )
    end
)


test.register_coroutine_test(
    "Setting window shade close should generate correct zwave messages when reverse preference is set",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.device_lifecycle():__queue_receive(mock_window_shade_switch_multilevel:generate_info_changed(
        {
            preferences = {
              reverse = true
            }
        }
      ))
      test.wait_for_events()
      test.socket.capability:__queue_receive(
          {
            mock_window_shade_switch_multilevel.id,
            { capability = "windowShade", command = "close", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_window_shade_switch_multilevel,
            SwitchMultilevel:Set({
              value = 99,
              duration = constants.DEFAULT_DIMMING_DURATION
            })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_window_shade_switch_multilevel,
            SwitchMultilevel:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting window shade level generate correct zwave messages when reverse preference is set",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.device_lifecycle():__queue_receive(mock_window_shade_switch_multilevel:generate_info_changed(
        {
            preferences = {
              reverse = true
            }
        }
      ))
      test.wait_for_events()
      test.socket.capability:__queue_receive(
          {
            mock_window_shade_switch_multilevel.id,
            { capability = "windowShadeLevel", command = "setShadeLevel", args = { 33 }}
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_window_shade_switch_multilevel,
            SwitchMultilevel:Set({
              value = 66,
              duration = constants.DEFAULT_DIMMING_DURATION
            })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_window_shade_switch_multilevel,
            SwitchMultilevel:Get({})
          )
      )
    end
)

test.run_registered_tests()
