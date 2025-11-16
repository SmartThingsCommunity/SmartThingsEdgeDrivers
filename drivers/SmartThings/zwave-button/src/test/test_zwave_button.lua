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
local SceneActivation = (require "st.zwave.CommandClass.SceneActivation")({ version=1 })
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({ version=1 })
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version=1 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local t_utils = require "integration_test.utils"

local button_endpoints = {
  {
    command_classes = {
      {value = zw.SCENE_ACTIVATION},
      {value = zw.CENTRAL_SCENE},
      {value = zw.BATTERY},
    }
  }
}

local mock= test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("button-generic.yml"),
  zwave_endpoints = button_endpoints
})

local function test_init()
  test.mock_device.add_test_device(mock)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Button Scene Activation should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock.id, zw_test_utils.zwave_test_build_receive_command(SceneActivation:Set({scene_id = 1})) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock:generate_test_message("main", capabilities.button.button.pushed({ state_change = true }))
      }
    }
)

test.register_message_test(
    "Button Scene Activation held should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock.id, zw_test_utils.zwave_test_build_receive_command(SceneActivation:Set({scene_id = 2})) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock:generate_test_message("main", capabilities.button.button.held({ state_change = true }))
      }
    }
)

test.register_message_test(
    "Central Scene notification Button pushed should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
          key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME}))
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock:generate_test_message("main", capabilities.button.button.pushed({ state_change = true }))
      }
    }
)

test.register_message_test(
    "Central Scene notification button held should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
          key_attributes=CentralScene.key_attributes.KEY_HELD_DOWN}))
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock:generate_test_message("main", capabilities.button.button.down_hold({ state_change = true }))
      }
    }
  )

test.register_coroutine_test(
    "Device Add should bootstrap UI state",
    function()
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock.id, "added" })

      test.socket.capability:__expect_send(
        mock:generate_test_message(
          "main",
          capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = { displayed = false }})
        )
      )
      test.socket.capability:__expect_send(
        mock:generate_test_message(
          "main",
          capabilities.button.numberOfButtons({ value = 1 }, {visibility = { displayed = false }})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock,
          Battery:Get({})
        )
      )
    end
  )


  test.register_message_test(
    "WakeUp.Notification should evoke state refresh Z-Wave GETs",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock.id, zw_test_utils.zwave_test_build_receive_command(WakeUp:Notification({})) }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock,
          WakeUp:IntervalGet({})
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock,
          Battery:Get({})
        )
      },
    }
)

test.run_registered_tests()
