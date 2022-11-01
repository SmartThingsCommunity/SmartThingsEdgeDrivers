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
local utils = require "st.utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local t_utils = require "integration_test.utils"

local LED_COLOR_CONTROL_PARAMETER_NUMBER = 13
local LED_GENERIC_SATURATION = 100
local INOVELLI_MANUFACTURER_ID = 0x031E
local INOVELLI_LZW31_PRODUCT_TYPE = 0x0003
local INOVELLI_DIMMER_PRODUCT_ID = 0x0001
local LED_BAR_COMPONENT_NAME = "LEDColorConfiguration"

local function huePercentToZwaveValue(value)
  if value <= 2 then
    return 0
  elseif value >= 98 then
    return 255
  else
    return utils.round(value / 100 * 255)
  end
end

local function zwaveValueToHuePercent(value)
  if value <= 2 then
    return 0
  elseif value >= 254 then
    return 100
  else
    return utils.round(value / 255 * 100)
  end
end

local inovelli_dimmer_endpoints = {
  {
    command_classes = {
      { value = zw.SWITCH_COLOR }
    }
  }
}

local mock_inovelli_dimmer = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("inovelli-dimmer.yml"),
  zwave_endpoints = inovelli_dimmer_endpoints,
  zwave_manufacturer_id = INOVELLI_MANUFACTURER_ID,
  zwave_product_type = INOVELLI_LZW31_PRODUCT_TYPE,
  zwave_product_id = INOVELLI_DIMMER_PRODUCT_ID
})

local function test_init()
  test.mock_device.add_test_device(mock_inovelli_dimmer)
end
test.set_test_init_function(test_init)

do
  --local hue = 33
  --local sat = 50
  local hue = 50
  local sat = 1
  test.register_coroutine_test(
    "Color Control capability setColor commands should evoke the correct Z-Wave SETs and GETs",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_inovelli_dimmer.id,
        {
          capability = "colorControl",
          command = "setColor",
          args = {
            {
              hue = hue,
              saturation = sat
            }
          }
        }
      })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_inovelli_dimmer,
          Configuration:Set({
            parameter_number=LED_COLOR_CONTROL_PARAMETER_NUMBER,
            configuration_value=huePercentToZwaveValue(hue),
            size=2
          })
        )
      )
      test.wait_for_events()
      test.mock_time.advance_time(2)
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_inovelli_dimmer,
          Configuration:Get({ parameter_number=LED_COLOR_CONTROL_PARAMETER_NUMBER })
        )
      )
    end
  )
end

do
  local color = 214
  test.register_message_test(
    "Z-Wave Configuration reports with LED color control parameter should evoke Color Control capability events",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_inovelli_dimmer.id,
          zw_test_utils.zwave_test_build_receive_command(
            Configuration:Report({
              parameter_number = LED_COLOR_CONTROL_PARAMETER_NUMBER,
              configuration_value = color
            })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_inovelli_dimmer:generate_test_message(LED_BAR_COMPONENT_NAME, capabilities.colorControl.hue(zwaveValueToHuePercent(color)))
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_inovelli_dimmer:generate_test_message(LED_BAR_COMPONENT_NAME, capabilities.colorControl.saturation(LED_GENERIC_SATURATION))
      }
    }
  )
end

test.run_registered_tests()
