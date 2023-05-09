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
local t_utils = require "integration_test.utils"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })

-- supported command classes
local qubino_flush_1_relay_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_BINARY},
      {value = zw.METER},
    }
  }
}

local mock_qubino_flush_1_relay = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("qubino-flush1-relay-temperature.yml"),
  zwave_endpoints = qubino_flush_1_relay_endpoints,
  zwave_manufacturer_id = 0x0159,
  zwave_product_type = 0x0002,
  zwave_product_id = 0x0052
})

local function  test_init()
  test.mock_device.add_test_device(mock_qubino_flush_1_relay)
end
test.set_test_init_function(test_init)

do
  local new_param_value = 1
  test.register_coroutine_test(
    "Parameter input1SwitchType should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_qubino_flush_1_relay:generate_info_changed({preferences = {input1SwitchType = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
                mock_qubino_flush_1_relay,
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
    "Parameter input2SwitchType should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_qubino_flush_1_relay:generate_info_changed({preferences = {input2SwitchType = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
                mock_qubino_flush_1_relay,
          Configuration:Set({
            parameter_number = 2,
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
      test.socket.device_lifecycle:__queue_receive(mock_qubino_flush_1_relay:generate_info_changed({preferences = {saveStateAfterPowerFail = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
                mock_qubino_flush_1_relay,
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
    "Parameter outputQ1SwitchSelection should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_qubino_flush_1_relay:generate_info_changed({preferences = {outputQ1SwitchSelection = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
                mock_qubino_flush_1_relay,
          Configuration:Set({
            parameter_number = 63,
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
    "Parameter outputQ2SwitchSelection should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_qubino_flush_1_relay:generate_info_changed({preferences = {outputQ2SwitchSelection = new_param_value}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
                mock_qubino_flush_1_relay,
          Configuration:Set({
            parameter_number = 64,
            configuration_value = new_param_value,
            size=1
          })
        )
      )
    end
  )
end

test.run_registered_tests()
