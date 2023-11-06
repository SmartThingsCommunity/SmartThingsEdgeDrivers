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
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"

local zwave_window_button_endpoint = {
  {
    command_classes = {
      {value = zw.BASIC}
    }
  }
}

local mock_window_button = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("stateless-curtain-power-button.yml"),
  zwave_endpoints = zwave_window_button_endpoint,
  zwave_manufacturer_id = 0x0086,
  zwave_product_type = 0x0003,
  zwave_product_id = 0x008D,
})

local function test_init()
  test.mock_device.add_test_device(mock_window_button)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Stateless curtain power button set open should be generate proper zwave command",
  function()
    test.socket.capability:__queue_receive(
        {
          mock_window_button.id,
          { capability = "statelessCurtainPowerButton", command = "setButton", args = { "open" } }
        }
    )
    test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_window_button,
          Basic:Set({ value = 0x00 })
        )
    )
  end
)

test.register_coroutine_test(
  "Stateless curtain power button set close should be generate proper zwave command",
  function()
    test.socket.capability:__queue_receive(
        {
          mock_window_button.id,
          { capability = "statelessCurtainPowerButton", command = "setButton", args = { "close" } }
        }
    )
    test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_window_button,
          Basic:Set({ value = 0xFF })
        )
    )
  end
)

test.register_coroutine_test(
  "When stateless curtain power button paused it should go to previous state (opening)",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_window_button.id,
        { capability = "statelessCurtainPowerButton", command = "setButton", args = { "open" } }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_window_button,
        Basic:Set({ value = 0x00 })
      )
    )
    test.socket.capability:__queue_receive(
      {
        mock_window_button.id,
        { capability = "statelessCurtainPowerButton", command = "setButton", args = { "pause" } }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_window_button,
        Basic:Set({ value = 0x00 })
      )
    )
  end
)

test.register_coroutine_test(
  "When stateless curtain power button paused it should go to previous state (closing)",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_window_button.id,
        { capability = "statelessCurtainPowerButton", command = "setButton", args = { "close" } }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_window_button,
        Basic:Set({ value = 0xFF })
      )
    )
    test.socket.zwave:__queue_receive(
      {
        mock_window_button.id,
        Basic:Report({ value = 0xFF})
      }
    )
    test.socket.capability:__queue_receive(
      {
        mock_window_button.id,
        { capability = "statelessCurtainPowerButton", command = "setButton", args = { "pause" } }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_window_button,
        Basic:Set({ value = 0xFF })
      )
    )
  end
)

test.register_coroutine_test(
  "Stateless curtain power button set open should be generate proper zwave command when reverse working direction is set",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_window_button:generate_info_changed(
      {
        preferences = {
          reverse = true
        }
      }
    ))
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_window_button.id,
        { capability = "statelessCurtainPowerButton", command = "setButton", args = { "open" } }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_window_button,
        Basic:Set({ value = 0xFF })
      )
    )
  end
)

test.register_coroutine_test(
  "Stateless curtain power button set close should be generate proper zwave command when reverse working direction is set",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_window_button:generate_info_changed(
      {
        preferences = {
          reverse = true
        }
      }
    ))
    test.wait_for_events()
  test.socket.capability:__queue_receive(
      {
        mock_window_button.id,
        { capability = "statelessCurtainPowerButton", command = "setButton", args = { "close" } }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_window_button,
        Basic:Set({ value = 0x00 })
      )
    )
  end
)

test.register_coroutine_test(
  "When stateless curtain power button paused it should go to previous state (opening) when reverse working direction is set",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_window_button:generate_info_changed(
      {
        preferences = {
          reverse = true
        }
      }
    ))
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_window_button.id,
        { capability = "statelessCurtainPowerButton", command = "setButton", args = { "open" } }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_window_button,
        Basic:Set({ value = 0xFF })
      )
    )
    test.socket.capability:__queue_receive(
      {
        mock_window_button.id,
        { capability = "statelessCurtainPowerButton", command = "setButton", args = { "pause" } }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_window_button,
        Basic:Set({ value = 0xFF })
      )
    )
  end
)

test.register_coroutine_test(
  "When stateless curtain power button paused it should go to previous state (closing) when reverse working direction is set",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_window_button:generate_info_changed(
      {
        preferences = {
          reverse = true
        }
      }
    ))
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_window_button.id,
        { capability = "statelessCurtainPowerButton", command = "setButton", args = { "close" } }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_window_button,
        Basic:Set({ value = 0x00 })
      )
    )
    test.socket.zwave:__queue_receive(
      {
        mock_window_button.id,
        Basic:Report({ value = 0x00})
      }
    )
    test.socket.capability:__queue_receive(
      {
        mock_window_button.id,
        { capability = "statelessCurtainPowerButton", command = "setButton", args = { "pause" } }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_window_button,
        Basic:Set({ value = 0x00 })
      )
    )
  end
)

test.register_coroutine_test(
  "doConfigure lifecycle event should generate the correct commands",
  function ()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_window_button.id, "doConfigure" })
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(mock_window_button, Configuration:Set({parameter_number = 80, size = 1, configuration_value = 1})))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(mock_window_button, Configuration:Set({parameter_number = 85, size = 1, configuration_value = 1})))
    mock_window_button:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_message_test(
  "Refresh should generate the correct commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_window_button.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_window_button:generate_test_message(
        "main",
        capabilities.statelessCurtainPowerButton.availableCurtainPowerButtons({"open", "close", "pause"},
        {visibility = {displayed = false}}))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_window_button,
        Basic:Get({})
      )
    },
  }
)

test.register_coroutine_test(
  "added lifecycle event should generate the correct events",
  function ()
    test.socket.device_lifecycle:__queue_receive({ mock_window_button.id, "added" })
    test.socket.capability:__expect_send(mock_window_button:generate_test_message(
      "main",
      capabilities.statelessCurtainPowerButton.availableCurtainPowerButtons({"open", "close", "pause"},
      {visibility = {displayed = false}}))
    )
  end
)

test.register_coroutine_test(
  "Set open close time preference should generated proper zwave commands",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_window_button:generate_info_changed(
      {
        preferences = {
          openCloseTiming = 100
        }
      }
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_window_button,
      Configuration:Set({parameter_number = 35, size = 1, configuration_value = 100})
    ))
  end
)

test.run_registered_tests()
