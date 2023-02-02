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
local t_utils = require "integration_test.utils"
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 2 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 2 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 2 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })

local fibaro_door_window_sensor_endpoints = {
  {
    command_classes = {
      { value = zw.BATTERY },
      { value = zw.CONFIGURATION },
      { value = zw.NOTIFICATION },
      { value = zw.SENSOR_MULTILEVEL },
      { value = zw.WAKE_UP }
    }
  }
}

local mock_fibaro_door_window_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("fibaro-door-window-sensor-2.yml"),
  zwave_endpoints = fibaro_door_window_sensor_endpoints,
  zwave_manufacturer_id = 0x010F,
  zwave_product_type = 0x0702,
  zwave_product_id = 0x2000
})

test.mock_device.add_test_device(mock_fibaro_door_window_sensor)

local function test_init()
    test.mock_device.add_test_device(mock_fibaro_door_window_sensor)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Alarm reports command should be handled as contact sensor open",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_fibaro_door_window_sensor.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
          z_wave_alarm_type = Alarm.z_wave_alarm_type.ACCESS_CONTROL,
          z_wave_alarm_event = 22
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_door_window_sensor:generate_test_message("main", capabilities.contactSensor.contact.open())
      }
    }
)

test.register_message_test(
    "Alarm reports command should be handled as contact sensor closed",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_fibaro_door_window_sensor.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
          z_wave_alarm_type = Alarm.z_wave_alarm_type.ACCESS_CONTROL,
          z_wave_alarm_event = 23
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_door_window_sensor:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
    }
)

test.register_message_test(
    "Alarm reports command should be handled as tamper alert detected",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_fibaro_door_window_sensor.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
          z_wave_alarm_type = Alarm.z_wave_alarm_type.BURGLAR,
          z_wave_alarm_event = Alarm.z_wave_alarm_event.burglar.TAMPERING_PRODUCT_COVER_REMOVED
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_door_window_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "Alarm reports command should be handled as tamper alert clear",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_fibaro_door_window_sensor.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
          z_wave_alarm_type = Alarm.z_wave_alarm_type.BURGLAR,
          z_wave_alarm_event = 0
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_door_window_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      }
    }
)

test.register_message_test(
    "Alarm reports command should be handled as temperature alarm cleared",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_fibaro_door_window_sensor.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
          z_wave_alarm_type = Alarm.z_wave_alarm_type.HEAT,
          z_wave_alarm_event = 0
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_door_window_sensor:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
      }
    }
)

test.register_message_test(
    "Alarm reports command should be handled as temperature alarm heat",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_fibaro_door_window_sensor.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
          z_wave_alarm_type = Alarm.z_wave_alarm_type.HEAT,
          z_wave_alarm_event = Alarm.z_wave_alarm_event.heat.OVERDETECTED
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_door_window_sensor:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.heat())
      }
    }
)

test.register_message_test(
    "Alarm reports command should be handled as temperature alarm freeze",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_fibaro_door_window_sensor.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
          z_wave_alarm_type = Alarm.z_wave_alarm_type.HEAT,
          z_wave_alarm_event = Alarm.z_wave_alarm_event.heat.UNDER_DETECTED
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_fibaro_door_window_sensor:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.freeze())
      }
    }
)

test.register_coroutine_test(
    "Configuration value sholud be updated when wakeup notification received",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive({mock_fibaro_door_window_sensor.id, "init"})
      test.socket.device_lifecycle():__queue_receive(mock_fibaro_door_window_sensor:generate_info_changed(
          {
              preferences = {
                doorWindowState = 1,
                visualLedIndications = 1,
                tamperCancelDelay = 500,
                cancelTamperReport = 0,
                tempMeasurementInterval = 1000,
                tempReportsThreshold = 28,
                temperatureAlarmReports = 3,
                highTempThreshold = 300,
                lowTempThreshold = 250
              }
          }
      ))
      test.wait_for_events()
      test.socket.zwave:__queue_receive(
        {
          mock_fibaro_door_window_sensor.id,
          WakeUp:Notification({})
        }
      )
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor,
          Configuration:Set({parameter_number = 1, size = 1, configuration_value = 1})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor,
          Configuration:Get({parameter_number = 1})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor,
          Configuration:Set({parameter_number = 2, size = 1, configuration_value = 1})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({parameter_number = 2})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor,
          Configuration:Set({parameter_number = 30, size = 2, configuration_value = 500})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({parameter_number = 30})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor,
          Configuration:Set({parameter_number = 31, size = 1, configuration_value = 0})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({parameter_number = 31})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor,
          Configuration:Set({parameter_number = 50, size = 2, configuration_value = 1000})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({parameter_number = 50})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor,
          Configuration:Set({parameter_number = 51, size = 2, configuration_value = 28})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({parameter_number = 51})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor,
          Configuration:Set({parameter_number = 54, size = 1, configuration_value = 3})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({parameter_number = 54})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor,
          Configuration:Set({parameter_number = 55, size = 2, configuration_value = 300})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({parameter_number = 55})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor,
          Configuration:Set({parameter_number = 56, size = 2, configuration_value = 250})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({parameter_number = 56})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Battery:Get({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
      ))
    end
)

test.register_coroutine_test(
    "Reporting interval value should be updated when wakeup notification received",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive({mock_fibaro_door_window_sensor.id, "init"})
      test.socket.device_lifecycle():__queue_receive(mock_fibaro_door_window_sensor:generate_info_changed(
          {
              preferences = {
                reportingInterval = 10
              }
          }
      ))
      test.wait_for_events()
      test.socket.zwave:__queue_receive(
        {
          mock_fibaro_door_window_sensor.id,
          WakeUp:Notification({})
        }
      )
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        WakeUp:IntervalSet({node_id = 0x00, seconds = 10 * 3600})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Battery:Get({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
      ))
    end
)

test.register_message_test(
  "device_added should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {mock_fibaro_door_window_sensor.id, "added"}
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_fibaro_door_window_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    -- },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_fibaro_door_window_sensor:generate_test_message("main", capabilities.contactSensor.contact.open())
    -- },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_fibaro_door_window_sensor:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    -- }
  }
)

test.run_registered_tests()
