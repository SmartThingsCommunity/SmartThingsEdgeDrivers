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
local utils = require "st.utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local t_utils = require "integration_test.utils"
local dkjson = require 'dkjson'

local INOVELLI_MANUFACTURER_ID = 0x031E
local INOVELLI_LZW31_PRODUCT_TYPE = 0x0003
local INOVELLI_DIMMER_PRODUCT_ID = 0x0001

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
  local new_param_value = 10
  test.register_coroutine_test(
    "Parameter 1 should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_inovelli_dimmer.raw_st_data)
      device_data.preferences["dimmingSpeed"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_inovelli_dimmer.id, "infoChanged", device_data_json })

      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_inovelli_dimmer,
          Configuration:Set({
            parameter_number = 1,
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
    "Parameter 1 should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_inovelli_dimmer.raw_st_data)
      device_data.preferences["powerOnState"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_inovelli_dimmer.id, "infoChanged", device_data_json })

      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_inovelli_dimmer,
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
  local new_param_value = 0
  test.register_coroutine_test(
    "Parameter 11 should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_inovelli_dimmer.raw_st_data)
      device_data.preferences["acPowerType"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_inovelli_dimmer.id, "infoChanged", device_data_json })

      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_inovelli_dimmer,
          Configuration:Set({
            parameter_number = 21,
            configuration_value = new_param_value,
            size=1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 10000
  test.register_coroutine_test(
    "Parameter 8 should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_inovelli_dimmer.raw_st_data)
      device_data.preferences["autoOffTimer"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_inovelli_dimmer.id, "infoChanged", device_data_json })

      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_inovelli_dimmer,
          Configuration:Set({
            parameter_number = 8,
            configuration_value = new_param_value,
            size=2
          })
        )
      )
    end
  )
end


do
  local new_param_value = 1
  test.register_coroutine_test(
    "Parameter 7 should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_inovelli_dimmer.raw_st_data)
      device_data.preferences["invertSwitch"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_inovelli_dimmer.id, "infoChanged", device_data_json })

      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_inovelli_dimmer,
          Configuration:Set({
            parameter_number = 7,
            configuration_value = new_param_value,
            size=1
          })
        )
      )
    end
  )
end


test.run_registered_tests()
