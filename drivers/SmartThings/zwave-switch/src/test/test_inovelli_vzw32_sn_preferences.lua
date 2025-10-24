-- Copyright 2025 SmartThings
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

-- Inovelli VZW32-SN device identifiers
local INOVELLI_MANUFACTURER_ID = 0x031E
local INOVELLI_VZW32_SN_PRODUCT_TYPE = 0x0017
local INOVELLI_VZW32_SN_PRODUCT_ID = 0x0001

-- Device endpoints with supported command classes
local inovelli_vzw32_sn_endpoints = {
  {
    command_classes = {
      { value = zw.SWITCH_BINARY },
      { value = zw.SWITCH_MULTILEVEL },
      { value = zw.BASIC },
      { value = zw.CONFIGURATION },
      { value = zw.CENTRAL_SCENE },
      { value = zw.ASSOCIATION },
    }
  }
}

-- Create mock device
local mock_inovelli_vzw32_sn = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("inovelli-mmwave-dimmer-vzw32-sn.yml"),
  zwave_endpoints = inovelli_vzw32_sn_endpoints,
  zwave_manufacturer_id = INOVELLI_MANUFACTURER_ID,
  zwave_product_type = INOVELLI_VZW32_SN_PRODUCT_TYPE,
  zwave_product_id = INOVELLI_VZW32_SN_PRODUCT_ID
})

local function test_init()
  test.mock_device.add_test_device(mock_inovelli_vzw32_sn)
end
test.set_test_init_function(test_init)

-- Test parameter 1 (example preference)
do
  local new_param_value = 10
  test.register_coroutine_test(
    "Parameter 1 should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_inovelli_vzw32_sn:generate_info_changed({preferences = {parameter1 = new_param_value}}))

      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_inovelli_vzw32_sn,
          Configuration:Set({
            parameter_number = 1,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

-- Test parameter 52 (example preference)
do
  local new_param_value = 25
  test.register_coroutine_test(
    "Parameter 52 should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_inovelli_vzw32_sn:generate_info_changed({preferences = {parameter52 = new_param_value}}))

      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_inovelli_vzw32_sn,
          Configuration:Set({
            parameter_number = 52,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

-- Test parameter 158 (example preference)
do
  local new_param_value = 5
  test.register_coroutine_test(
    "Parameter 158 should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_inovelli_vzw32_sn:generate_info_changed({preferences = {parameter158 = new_param_value}}))

      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_inovelli_vzw32_sn,
          Configuration:Set({
            parameter_number = 158,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

-- Test parameter 101 (2-byte parameter)
do
  local new_param_value = -400
  test.register_coroutine_test(
    "Parameter 101 should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_inovelli_vzw32_sn:generate_info_changed({preferences = {parameter101 = new_param_value}}))

      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_inovelli_vzw32_sn,
          Configuration:Set({
            parameter_number = 101,
            configuration_value = new_param_value,
            size = 2
          })
        )
      )
    end
  )
end

-- Test notificationChild preference (special case for child device creation)
do
  local new_param_value = true
  test.register_coroutine_test(
    "notificationChild preference should create child device when enabled",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_inovelli_vzw32_sn:generate_info_changed({preferences = {notificationChild = new_param_value}}))

      -- Expect child device creation
      mock_inovelli_vzw32_sn:expect_device_create({
        type = "EDGE_CHILD",
        label = "nil Notification", -- This will be the parent label + "Notification"
        profile = "rgbw-bulb",
        parent_device_id = mock_inovelli_vzw32_sn.id,
        parent_assigned_child_key = "notification"
      })
    end
  )
end

test.run_registered_tests()