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
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=3 })
local t_utils = require "integration_test.utils"

-- supported comand classes: SWITCH_MULTILEVEL
local zwave_blind_endpoint = {
  {
    command_classes = {
      {value = zw.CONFIGURATION},
      {value = zw.SWITCH_MULTILEVEL}
    }
  }
}

local mock_blind = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("window-treatment-preset-reverse.yml"),
  zwave_endpoints = zwave_blind_endpoint,
  zwave_manufacturer_id = 0x0287,
  zwave_product_type = 0x0003,
  zwave_product_id = 0x000D
})

local mock_blind_v3 = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("iblinds-window-treatment-v3.yml"),
  zwave_endpoints = zwave_blind_endpoint,
  zwave_manufacturer_id = 0x0287,
  zwave_product_type = 0x0004,
  zwave_product_id = 0x0071
})

local function test_init()
  test.mock_device.add_test_device(mock_blind)
  test.mock_device.add_test_device(mock_blind_v3)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Setting window shade open should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_blind.id,
            { capability = "windowShade", command = "open", args = {} }
          }
      )
      test.socket.capability:__expect_send(
        mock_blind:generate_test_message("main", capabilities.windowShade.windowShade.open())
      )
      test.socket.capability:__expect_send(
        mock_blind:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50))
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_blind,
            SwitchMultilevel:Set({
              value = 50
            })
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
            mock_blind.id,
            { capability = "windowShade", command = "close", args = {} }
          }
      )
      test.socket.capability:__expect_send(
        mock_blind:generate_test_message("main", capabilities.windowShade.windowShade.closed())
      )
      test.socket.capability:__expect_send(
        mock_blind:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_blind,
            SwitchMultilevel:Set({
              value = 0
            })
          )
      )
    end
)

test.register_coroutine_test(
    "Setting window shade close should generate correct zwave messages when revese direction",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive({mock_blind.id, "init"})
      test.socket.device_lifecycle():__queue_receive(mock_blind:generate_info_changed(
          {
              preferences = {
                reverse = true
              }
          }
      ))
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_blind.id,
          { capability = "windowShade", command = "close", args = {} }
        }
      )
      test.socket.capability:__expect_send(
        mock_blind:generate_test_message("main", capabilities.windowShade.windowShade.closed())
      )
      test.socket.capability:__expect_send(
        mock_blind:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(99))
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_blind,
            SwitchMultilevel:Set({
              value = 99
            })
          )
      )
      end
)

test.register_coroutine_test(
    "Setting window shade level should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_blind.id,
            { capability = "windowShadeLevel", command = "setShadeLevel", args = { 33 } }
          }
      )
      test.socket.capability:__expect_send(
        mock_blind:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      )
      test.socket.capability:__expect_send(
        mock_blind:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(33))
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_blind,
            SwitchMultilevel:Set({
              value = 33
            })
          )
      )
    end
)

test.register_coroutine_test(
    "Setting window shade level should generate correct zwave messages when revese direction",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive({mock_blind.id, "init"})
      test.socket.device_lifecycle():__queue_receive(mock_blind:generate_info_changed(
          {
              preferences = {
                reverse = true
              }
          }
      ))
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_blind.id,
          { capability = "windowShadeLevel", command = "setShadeLevel", args = {33} }
        }
      )
      test.socket.capability:__expect_send(
        mock_blind:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      )
      test.socket.capability:__expect_send(
        mock_blind:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(66))
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_blind,
            SwitchMultilevel:Set({
              value = 66
            })
          )
      )
      end
)

test.register_coroutine_test(
    "Setting window shade preset position should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
        {
          mock_blind.id,
          { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {} }
        }
      )
      test.socket.capability:__expect_send(
        mock_blind:generate_test_message("main", capabilities.windowShade.windowShade.open())
      )
      test.socket.capability:__expect_send(
        mock_blind:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50))
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_blind,
            SwitchMultilevel:Set({
              value = 50
            })
          )
      )
      end
)

test.register_coroutine_test(
    "Setting window shade preset position should generate correct zwave messages when pre-defined value is set",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive({mock_blind.id, "init"})
      test.socket.device_lifecycle():__queue_receive(mock_blind:generate_info_changed(
          {
              preferences = {
                presetPosition = 35
              }
          }
      ))
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_blind.id,
          { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {} }
        }
      )
      test.socket.capability:__expect_send(
        mock_blind:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      )
      test.socket.capability:__expect_send(
        mock_blind:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(35))
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_blind,
            SwitchMultilevel:Set({
              value = 35
            })
          )
      )
      end
)

test.register_coroutine_test(
    "Setting window shade close should generate correct zwave messages for v3 model",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_blind_v3.id,
            { capability = "windowShade", command = "close", args = {} }
          }
      )
      test.socket.capability:__expect_send(
        mock_blind_v3:generate_test_message("main", capabilities.windowShade.windowShade.closed())
      )
      test.socket.capability:__expect_send(
        mock_blind_v3:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_blind_v3,
            SwitchMultilevel:Set({
              value = 0
            })
          )
      )
    end
)

test.register_coroutine_test(
    "Setting window shade level should generate correct zwave messages for v3 model",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_blind_v3.id,
          { capability = "windowShadeLevel", command = "setShadeLevel", args = {33} }
        }
      )
      test.socket.capability:__expect_send(
        mock_blind_v3:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      )
      test.socket.capability:__expect_send(
        mock_blind_v3:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(33))
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_blind_v3,
            SwitchMultilevel:Set({
              value = 33
            })
          )
      )
      end
)

test.register_coroutine_test(
    "Setting window shade level should generate correct zwave messages when revese direction for v3 model",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive({mock_blind_v3.id, "init"})
      test.socket.device_lifecycle():__queue_receive(mock_blind_v3:generate_info_changed(
          {
              preferences = {
                defaultOnValue = 37
              }
          }
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_blind_v3,
        Configuration:Set({parameter_number = 4, size = 1, configuration_value = 37})
      ))
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_blind_v3.id,
          { capability = "windowShadeLevel", command = "setShadeLevel", args = {37} }
        }
      )
      test.socket.capability:__expect_send(
        mock_blind_v3:generate_test_message("main", capabilities.windowShade.windowShade.open())
      )
      test.socket.capability:__expect_send(
        mock_blind_v3:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(37))
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_blind_v3,
            SwitchMultilevel:Set({
              value = 37
            })
          )
      )
      end
)

test.register_coroutine_test(
    "Setting window shade preset position should generate correct zwave messages for v3 model",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
        {
          mock_blind_v3.id,
          { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {} }
        }
      )
      test.socket.capability:__expect_send(
        mock_blind_v3:generate_test_message("main", capabilities.windowShade.windowShade.open())
      )
      test.socket.capability:__expect_send(
        mock_blind_v3:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50))
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_blind_v3,
            SwitchMultilevel:Set({
              value = 50
            })
          )
      )
      end
)

test.register_coroutine_test(
    "Setting window shade preset position should generate correct zwave messages when pre-defined value is set for v3 model",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive({mock_blind_v3.id, "init"})
      test.socket.device_lifecycle():__queue_receive(mock_blind_v3:generate_info_changed(
          {
              preferences = {
                defaultOnValue = 40
              }
          }
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_blind_v3,
        Configuration:Set({parameter_number = 4, size = 1, configuration_value = 40})
      ))
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_blind_v3.id,
          { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {} }
        }
      )
      test.socket.capability:__expect_send(
        mock_blind_v3:generate_test_message("main", capabilities.windowShade.windowShade.open())
      )
      test.socket.capability:__expect_send(
        mock_blind_v3:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(40))
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_blind_v3,
            SwitchMultilevel:Set({
              value = 40
            })
          )
      )
      end
)

test.register_coroutine_test(
    "Configuration value sholud be updated when update preference",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive({mock_blind_v3.id, "init"})
      test.socket.device_lifecycle():__queue_receive(mock_blind_v3:generate_info_changed(
          {
              preferences = {
                closeInterval = 10,
                reverse = true,
                defaultOnValue = 20,
                disableResetButton = true,
                openCloseSpeed = 50
              }
          }
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_blind_v3,
          Configuration:Set({parameter_number = 1, size = 1, configuration_value = 10})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_blind_v3,
          Configuration:Set({parameter_number = 2, size = 1, configuration_value = 1})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_blind_v3,
          Configuration:Set({parameter_number = 4, size = 1, configuration_value = 20})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_blind_v3,
          Configuration:Set({parameter_number = 5, size = 1, configuration_value = 1})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_blind_v3,
          Configuration:Set({parameter_number = 6, size = 1, configuration_value = 50})
      ))
    end
)

test.run_registered_tests()
