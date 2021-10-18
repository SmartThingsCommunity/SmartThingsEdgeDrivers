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
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"

local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
local SensorAlarm = (require "st.zwave.CommandClass.SensorAlarm")({ version = 1 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 2 })

-- supported comand classes
local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.SENSOR_BINARY},
      {value = zw.SENSOR_ALARM},
      {value = zw.NOTIFICATION},
      {value = zw.ALARM},
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("smoke-co-battery.yml"),
    zwave_endpoints = sensor_endpoints
  }
)

local function  test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Sensor Binary report (CO) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorBinary:Report({
          sensor_type = SensorBinary.sensor_type.CO,
          sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.detected())
      }
    }
)

test.register_message_test(
    "Sensor Alarm report (CO) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorAlarm:Report({
          sensor_type = SensorAlarm.sensor_type.CO_ALARM,
          sensor_state = SensorAlarm.sensor_state.ALARM
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.detected())
      },
    }
)
test.register_message_test(
    "Sensor Alarm report (CO clear) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorAlarm:Report({
          sensor_type = SensorAlarm.sensor_type.CO_ALARM,
          sensor_state = SensorAlarm.sensor_state.NO_ALARM
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
      },
    }
)

test.register_message_test(
    "Notification report (CO) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.CO,
          event = Notification.event.co.CARBON_MONOXIDE_DETECTED
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.detected())
      }
    }
)

test.register_message_test(
    "Notification test report (CO) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.CO,
          event = Notification.event.co.CARBON_MONOXIDE_TEST
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.tested())
      }
    }
)

test.register_message_test(
    "Notification clear report (CO) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.CO,
          event = Notification.event.co.UNKNOWN_EVENT_STATE
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
      }
    }
)

test.register_message_test(
    "Alarm report (CO detected) should be ignored",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
          alarm_type = Alarm.z_wave_alarm_type.CO,
          alarm_level = 1
        })) }
      },
    }
)

test.run_registered_tests()
