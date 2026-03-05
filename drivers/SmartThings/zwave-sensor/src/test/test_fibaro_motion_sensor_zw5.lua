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
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 8 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.SENSOR_MULTILEVEL},
      {value = zw.CONFIGURATION},
      {value = zw.WAKE_UP}
    }
  }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("fibaro-motion-sensor.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x010F,
  zwave_product_type = 0x0801,
  zwave_product_id = 0x1001
})

local function test_init()
  test.mock_device.add_test_device(mock_sensor)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Three Axis reports should be correctly handled",
  function()
    test.socket.zwave:__queue_receive({
      mock_sensor.id,
      SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.ACCELERATION_X_AXIS,
        sensor_value = 1.962,
        scale = SensorMultilevel.scale.acceleration_x_axis.METERS_PER_SQUARE_SECOND }
      )
    })
    test.socket.zwave:__queue_receive({
      mock_sensor.id,
      SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.ACCELERATION_Y_AXIS,
        sensor_value = 1.962,
        scale = SensorMultilevel.scale.acceleration_y_axis.METERS_PER_SQUARE_SECOND }
      )
    })
    test.socket.zwave:__queue_receive({
      mock_sensor.id,
      SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.ACCELERATION_Z_AXIS,
        sensor_value = 3.924,
        scale = SensorMultilevel.scale.acceleration_z_axis.METERS_PER_SQUARE_SECOND }
      )
    })
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main",
        capabilities.threeAxis.threeAxis({value = {200, 200, 400}, unit = 'mG'})
      )
    )
  end
)

test.register_coroutine_test(
    "New configuration paramaters should be send and device should be refreshed after device wakes up",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive({mock_sensor.id, "init"})
      test.socket.device_lifecycle():__queue_receive(mock_sensor:generate_info_changed(
          {
              preferences = {
                motionSensitivityLevel = 100,
                motionBlindTime = 3,
                motionCancelationDelay = 100,
                motionOperatingMode = 1,
                motionNightDay = 300,
                tamperCancelationDelay = 100,
                tamperOperatingMode = 1,
                illuminanceThreshold = 100,
                illuminanceInterval = 7200,
                temperatureThreshold = 6,
                ledMode = 22,
                ledBrightness = 100,
                ledLowBrightness = 200,
                ledHighBrightness = 30000
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
          Configuration:Set({parameter_number = 1, size = 2, configuration_value = 100})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          WakeUp:IntervalGet({})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 2, size = 1, configuration_value = 3})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 6, size = 2, configuration_value = 100})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 8, size = 1, configuration_value = 1})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 9, size = 2, configuration_value = 300})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 22, size = 2, configuration_value = 100})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 24, size = 1, configuration_value = 1})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 40, size = 2, configuration_value = 100})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 42, size = 2, configuration_value = 7200})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 60, size = 2, configuration_value = 6})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 80, size = 1, configuration_value = 22})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 81, size = 1, configuration_value = 100})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 82, size = 2, configuration_value = 200})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 83, size = 2, configuration_value = 30000})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.LUMINANCE, scale = 0x01})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.ACCELERATION_X_AXIS, scale = SensorMultilevel.scale.acceleration_x_axis.METERS_PER_SQUARE_SECOND})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.ACCELERATION_Y_AXIS, scale = SensorMultilevel.scale.acceleration_y_axis.METERS_PER_SQUARE_SECOND})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.ACCELERATION_Z_AXIS, scale = SensorMultilevel.scale.acceleration_z_axis.METERS_PER_SQUARE_SECOND})
      ))
    end
)

test.run_registered_tests()
