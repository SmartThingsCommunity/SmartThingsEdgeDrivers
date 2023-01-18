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
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = zw.NOTIFICATION},
      {value = zw.SENSOR_MULTILEVEL}
    }
  }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("multi-functional-motion.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x027A,
  zwave_product_type = 0x2021,
  zwave_product_id = 0x2101,
})

local function test_init()
  test.mock_device.add_test_device(mock_sensor)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Notification report 0xFF should be handled as motion active",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_status = 0xFF,
          notification_type = Notification.notification_type.HOME_SECURITY,
          event = Notification.event.home_security.MOTION_DETECTION,
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "Notification report 0x00 should be handled as motion inactive",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_status = 0x00,
          notification_type = Notification.notification_type.HOME_SECURITY,
          event = Notification.event.home_security.MOTION_DETECTION,
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    }
)

test.register_coroutine_test(
    "Notification report TAMPERING_PRODUCT_COVER_REMOVED event should be handled as tamperAlert detected and back to clear after 10 secs",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(10, "oneshot")
      test.socket.zwave:__queue_receive(
        {
          mock_sensor.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report(
                  {
                    notification_type = Notification.notification_type.HOME_SECURITY,
                    event = Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED
                  })
          )

        }
      )
      test.socket.capability:__expect_send(mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.detected()))
      test.wait_for_events()
      test.mock_time.advance_time(10)
      test.socket.capability:__expect_send(mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
    end
)

test.register_message_test(
    "Notification report STATE_IDLE event should be handled as tamperAlert clear",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HOME_SECURITY,
          event = Notification.event.home_security.STATE_IDLE,
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      }
    }
)

test.register_message_test(
    "Notification report STATE_IDLE event and specific event parameter should be handled as motion inactive",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HOME_SECURITY,
          event = Notification.event.home_security.STATE_IDLE,
          event_parameter = ''
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    }
)

test.register_message_test(
  "Sensor multilevel reports luminance type command should be handled as illuminance measurement",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.LUMINANCE,
        sensor_value = 26.24 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance({value = 131, unit = "lux"}))
    }
  }
)

test.register_message_test(
  "Sensor multilevel reports temperature type command should be handled as temperature measurement",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        sensor_value = 80.25,
        scale = 1
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 80.25, unit = "F"}))
    }
  }
)

test.register_message_test(
  "Sensor multilevel reports relative humidity type command should be handled as relative humidity measurement",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY,
        sensor_value = 52.92
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 53 }))
    }
  }
)

test.register_message_test(
  "Refresh Capability Command should refresh Thermostat device",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {mock_sensor.id, "added"}
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    -- },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    -- }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.run_registered_tests()
