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
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = zw.NOTIFICATION},
      {value = zw.SENSOR_MULTILEVEL},
      {value = zw.WAKE_UP}
    }
  }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("water-temperature-humidity-tamper-battery.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0102,
  zwave_product_id = 0x0013,
})

local function test_init()
  test.mock_device.add_test_device(mock_sensor)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Notification report LEAK_DETECTED_LOCATION_PROVIDED event should be handled water sensor state wet",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.WATER,
          event = Notification.event.water.LEAK_DETECTED_LOCATION_PROVIDED,
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_sensor:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "Notification report LEAK_DETECTED event should be handled water sensor state wet",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.WATER,
          event = Notification.event.water.LEAK_DETECTED,
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_sensor:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "Notification report STATE_IDLE event should be handled water sensor state dry",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.WATER,
          event = Notification.event.water.STATE_IDLE,
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_sensor:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "Notification report UNKNOWN_EVENT_STATE event should be handled water sensor state dry",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.WATER,
          event = Notification.event.water.UNKNOWN_EVENT_STATE,
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_sensor:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "Notification report STATE_IDLE event should be handled tamper alert state clear",
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

test.run_registered_tests()
