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
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({version=1})
local t_utils = require "integration_test.utils"

local INOVELLI_MANUFACTURER_ID = 0x031E
local INOVELLI_LZW31_SN_PRODUCT_TYPE = 0x0001
local INOVELLI_DIMMER_PRODUCT_ID = 0x0001
local LED_BAR_COMPONENT_NAME = "LEDColorConfiguration"

local BUTTON_UP_SCENE_2 = 2
local BUTTON_DOWN_SCENE_1 = 1
local BUTTON_CONFIGURE_SCENE_3 = 3

local inovelli_dimmer_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC }
    }
  },
  {
    command_classes = {
      { value = zw.CENTRAL_SCENE }
    }
  },
  {
    command_classes = {
      { value = zw.CENTRAL_SCENE }
    }
  },
  {
    command_classes = {
      { value = zw.CENTRAL_SCENE }
    }
  },
}

local mock_inovelli_dimmer = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("inovelli-dimmer-power-energy.yml"),
  zwave_endpoints = inovelli_dimmer_endpoints,
  zwave_manufacturer_id = INOVELLI_MANUFACTURER_ID,
  zwave_product_type = INOVELLI_LZW31_SN_PRODUCT_TYPE,
  zwave_product_id = INOVELLI_DIMMER_PRODUCT_ID
})

local function test_init()
  test.mock_device.add_test_device(mock_inovelli_dimmer)
end
test.set_test_init_function(test_init)

local supported_button_values = {
  ["button1"] = {"pushed", "pushed_2x", "pushed_3x", "pushed_4x", "pushed_5x"},
  ["button2"] = {"pushed", "pushed_2x", "pushed_3x", "pushed_4x", "pushed_5x"},
  ["button3"] = {"pushed"}
}

test.register_coroutine_test(
  "added lifecycle event",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_inovelli_dimmer.id, "added" })

    for button_name, _ in pairs(mock_inovelli_dimmer.profile.components) do
      if button_name ~= "main" and button_name ~= LED_BAR_COMPONENT_NAME then
        test.socket.capability:__expect_send(
          mock_inovelli_dimmer:generate_test_message(
            button_name,
            capabilities.button.supportedButtonValues(
              supported_button_values[button_name],
              { visibility = { displayed = false } }
            )
          )
        )
        test.socket.capability:__expect_send(
          mock_inovelli_dimmer:generate_test_message(
            button_name,
            capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
          )
        )
      end
    end

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_dimmer,
        Basic:Get({})
      )
    )
  end
)


test.register_message_test(
  "Central Scene notification Button 1 pushed should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_inovelli_dimmer.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_inovelli_dimmer.id,
                  zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({ key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME, scene_number = BUTTON_UP_SCENE_2},
                  { encap = zw.ENCAP.AUTO, src_channel = 1, dst_channels = {0} }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_dimmer:generate_test_message("button1", capabilities.button.button.pushed({state_change = true}))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 2 pushed x4 should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_inovelli_dimmer.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_inovelli_dimmer.id,
                  zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({ key_attributes=CentralScene.key_attributes.KEY_PRESSED_4_TIMES, scene_number = BUTTON_DOWN_SCENE_1},
                    { encap = zw.ENCAP.AUTO, src_channel = 2, dst_channels = {0} }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_dimmer:generate_test_message("button2", capabilities.button.button.pushed_4x({ state_change = true }))
    }
  }
)

test.register_message_test(
    "Central Scene notification Button 3 pushed should be handled",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_inovelli_dimmer.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_inovelli_dimmer.id,
                    zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({ key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME, scene_number = BUTTON_CONFIGURE_SCENE_3},
                      { encap = zw.ENCAP.AUTO, src_channel = 3, dst_channels = {0} }))
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_inovelli_dimmer:generate_test_message("button3", capabilities.button.button.pushed({state_change = true}))
      }
    }
)

test.run_registered_tests()
