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
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.CONFIGURATION},
      {value = zw.WAKE_UP}
    }
  }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("water-battery-tamper-temperature.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x010F,
  zwave_product_type = 0x0B01,
  zwave_product_id = 0x1002
})

local function test_init()
  test.mock_device.add_test_device(mock_sensor)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Reporting interval value sholud be updated when wakeup notification received",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive({mock_sensor.id, "init"})
      test.socket.device_lifecycle():__queue_receive(mock_sensor:generate_info_changed(
          {
              preferences = {
                alarmCancellationDelay = 600,
                acousticVisualSignals = 2,
                tempMeasurementInterval = 1000,
                floodSensorTurnedOnOff = 2
              }
          }
      ))
      test.wait_for_events()
      test.socket.zwave:__queue_receive(
        {
          mock_sensor.id,
          WakeUp:Notification({})
        }
      )

      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          WakeUp:IntervalGet({})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 1, size = 2, configuration_value = 600})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 2, size = 1, configuration_value = 2})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 10, size = 4, configuration_value = 1000})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 77, size = 1, configuration_value = 2})
      ))
    end
)

test.run_registered_tests()
