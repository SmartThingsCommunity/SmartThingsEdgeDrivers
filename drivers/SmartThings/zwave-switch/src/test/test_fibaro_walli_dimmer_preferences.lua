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
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local t_utils = require "integration_test.utils"

local FIBARO_WALLI_DIMMER_MANUFACTURER_ID = 0x010F
local FIBARO_WALLI_DIMMER_PRODUCT_TYPE = 0x1C01
local FIBARO_WALLI_DIMMER_PRODUCT_ID = 0x1000

local fibaro_walli_dimmer_endpoints = {
  {
    command_classes = {
      {value = zw.METER},
      {value = zw.BASIC},
      {value = zw.SWITCH_BINARY},
      {value = zw.SWITCH_MULTILEVEL}
    }
  }
}

local mock_fibaro_walli_dimmer = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("fibaro-walli-dimmer.yml"),
  zwave_endpoints = fibaro_walli_dimmer_endpoints,
  zwave_manufacturer_id = FIBARO_WALLI_DIMMER_MANUFACTURER_ID,
  zwave_product_type = FIBARO_WALLI_DIMMER_PRODUCT_TYPE,
  zwave_product_id = FIBARO_WALLI_DIMMER_PRODUCT_ID
})

local function test_init()
  test.mock_device.add_test_device(mock_fibaro_walli_dimmer)
end
test.set_test_init_function(test_init)

do
  local new_param_value = 7
  test.register_coroutine_test(
    "Parameter 11 (ledFrameColourWhenOn) should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_fibaro_walli_dimmer:generate_info_changed({preferences = {ledFrameColourWhenOn = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_walli_dimmer,
          Configuration:Set({
            parameter_number = 11,
            configuration_value = new_param_value,
            size=1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 1
  test.register_coroutine_test(
    "Parameter 12 (ledFrameColourWhenOff) should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_fibaro_walli_dimmer:generate_info_changed({preferences = {ledFrameColourWhenOff = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_walli_dimmer,
          Configuration:Set({
            parameter_number = 12,
            configuration_value = new_param_value,
            size=1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 50
  test.register_coroutine_test(
    "Parameter 13 (ledFrameBrightness) should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_fibaro_walli_dimmer:generate_info_changed({preferences = {ledFrameBrightness = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_walli_dimmer,
          Configuration:Set({
            parameter_number = 13,
            configuration_value = new_param_value,
            size=1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 10
  test.register_coroutine_test(
    "Parameter 156 (dimmStepSizeManControl) should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_fibaro_walli_dimmer:generate_info_changed({preferences = {dimmStepSizeManControl = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_walli_dimmer,
          Configuration:Set({
            parameter_number = 156,
            configuration_value = new_param_value,
            size=1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 75
  test.register_coroutine_test(
    "Parameter 157 (timeToPerformDimmingStep) should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_fibaro_walli_dimmer:generate_info_changed({preferences = {timeToPerformDimmingStep = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_walli_dimmer,
          Configuration:Set({
            parameter_number = 157,
            configuration_value = new_param_value,
            size=2
          })
        )
      )
    end
  )
end


do
  local new_param_value = 30
  test.register_coroutine_test(
    "Parameter 165 (doubleClickSetLevel) should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_fibaro_walli_dimmer:generate_info_changed({preferences = {doubleClickSetLevel = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_walli_dimmer,
          Configuration:Set({
            parameter_number = 165,
            configuration_value = new_param_value,
            size=1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 1
  test.register_coroutine_test(
    "Parameter 24 (buttonsOrientation) should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_fibaro_walli_dimmer:generate_info_changed({preferences = {buttonsOrientation = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
                mock_fibaro_walli_dimmer,
          Configuration:Set({
            parameter_number = 24,
            configuration_value = new_param_value,
            size=1
          })
        )
      )
    end
  )
end

test.run_registered_tests()
