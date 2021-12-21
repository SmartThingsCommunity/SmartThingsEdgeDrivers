-- Copyright 2021 SmartThings
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
local t_utils = require "integration_test.utils"
local utils = require "st.utils"
local dkjson = require 'dkjson'
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })

-- supported command classes
local qubino_flush_dimmer_0_10V_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.SWITCH_BINARY},
      {value = zw.SWITCH_MULTILEVEL},
      {value = zw.SENSOR_MULTILEVEL}
    }
  }
}

local mock_qubino_flush_dimmer_0_10V = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("qubino-flush-dimmer-0-10V-temperature.yml"),
  zwave_endpoints = qubino_flush_dimmer_0_10V_endpoints,
  zwave_manufacturer_id = 0x0159,
  zwave_product_type = 0x0001,
  zwave_product_id = 0x0053
})

local function  test_init()
  test.mock_device.add_test_device(mock_qubino_flush_dimmer_0_10V)
end
test.set_test_init_function(test_init)

do
  local new_param_value = 2
  test.register_coroutine_test(
    "Parameter input1SwitchType should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_qubino_flush_dimmer_0_10V:generate_info_changed({preferences = {input1SwitchType = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
                mock_qubino_flush_dimmer_0_10V,
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
  local new_param_value = 1
  test.register_coroutine_test(
    "Parameter enableDoubleClick should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_qubino_flush_dimmer_0_10V:generate_info_changed({preferences = {enableDoubleClick = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
                mock_qubino_flush_dimmer_0_10V,
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
  local new_param_value = 1
  test.register_coroutine_test(
    "Parameter saveStateAfterPowerFail should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_qubino_flush_dimmer_0_10V:generate_info_changed({preferences = {saveStateAfterPowerFail = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
                mock_qubino_flush_dimmer_0_10V,
          Configuration:Set({
            parameter_number = 30,
            configuration_value = new_param_value,
            size=1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 5
  test.register_coroutine_test(
    "Parameter minimumDimmingValue should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_qubino_flush_dimmer_0_10V:generate_info_changed({preferences = {minimumDimmingValue = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
                mock_qubino_flush_dimmer_0_10V,
          Configuration:Set({
            parameter_number = 60,
            configuration_value = new_param_value,
            size=1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 5
  test.register_coroutine_test(
    "Parameter dimmingTimeSoftOnOff should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_qubino_flush_dimmer_0_10V:generate_info_changed({preferences = {dimmingTimeSoftOnOff = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
                mock_qubino_flush_dimmer_0_10V,
          Configuration:Set({
            parameter_number = 65,
            configuration_value = new_param_value,
            size=2
          })
        )
      )
    end
  )
end


do
  local new_param_value = 5
  test.register_coroutine_test(
    "Parameter dimmingTimeKeyPressed should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_qubino_flush_dimmer_0_10V.raw_st_data)
      device_data.preferences["dimmingTimeKeyPressed"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_qubino_flush_dimmer_0_10V.id, "infoChanged", device_data_json })
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
                mock_qubino_flush_dimmer_0_10V,
          Configuration:Set({
            parameter_number = 66,
            configuration_value = new_param_value,
            size=1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 5
  test.register_coroutine_test(
    "Parameter dimmingDuration should be updated in the device configuration after change",
    function()
      local device_data = utils.deep_copy(mock_qubino_flush_dimmer_0_10V.raw_st_data)
      device_data.preferences["dimmingDuration"] = new_param_value
      local device_data_json = dkjson.encode(device_data)
      test.socket.device_lifecycle:__queue_receive({ mock_qubino_flush_dimmer_0_10V.id, "infoChanged", device_data_json })

      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
                mock_qubino_flush_dimmer_0_10V,
          Configuration:Set({
            parameter_number = 68,
            configuration_value = new_param_value,
            size=1
          })
        )
      )
    end
  )
end

test.run_registered_tests()
