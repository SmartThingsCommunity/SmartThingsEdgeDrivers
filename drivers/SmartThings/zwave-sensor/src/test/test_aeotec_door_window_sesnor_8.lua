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
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 11 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = zw.NOTIFICATION},
      {value = zw.SENSOR_MULTILEVEL},
      {value = zw.CONFIGURATION}
    }
  }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-door-window-sensor-8.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_id = 0x0037,
})

local function test_init()
  test.mock_device.add_test_device(mock_sensor)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Device added lifecycle event for profile",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_sensor.id, "added" })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        Configuration:Get({
          parameter_number = 10
        })
      )
    )
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.moldHealthConcern.supportedMoldValues({"good", "moderate"}))
    )

    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.moldHealthConcern.moldHealthConcern.good())
    )

    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.powerSource.powerSource.battery())
    )


    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        Battery:Get({})
      )
    )
  end
)

test.register_message_test(
  "Refresh should generate the correct commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_sensor.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        Battery:Get({})
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- test.register_message_test(
--     "Notification report STATE_IDLE event should be handled as tamperAlert clear",
--     {
--       {
--         channel = "zwave",
--         direction = "receive",
--         message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
--           notification_type = Notification.notification_type.HOME_SECURITY,
--           event = Notification.event.home_security.STATE_IDLE,
--         })) }
--       },
--       {
--         channel = "capability",
--         direction = "send",
--         message = mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
--       }
--     }
-- )

-- test.register_message_test(
--     "Notification report TAMPERING_PRODUCT_COVER_REMOVED event should be handled as tamperAlert detected",
--     {
--       {
--         channel = "zwave",
--         direction = "receive",
--         message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
--           notification_type = Notification.notification_type.HOME_SECURITY,
--           event = Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED,
--         })) }
--       },
--       {
--         channel = "capability",
--         direction = "send",
--         message = mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
--       }
--     }
-- )

-- test.register_message_test(
--     "Battery report should be handled",
--     {
--       {
--         channel = "zwave",
--         direction = "receive",
--         message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Battery:Report({ battery_level = 0x63 })) }
--       },
--       {
--         channel = "capability",
--         direction = "send",
--         message = mock_sensor:generate_test_message("main", capabilities.battery.battery(99))
--       }
--     }
-- )

-- test.register_message_test(
--   "Notification report AC_MAINS_DISCONNECTED event should be handled power source state battery",
--   {
--     {
--       channel = "zwave",
--       direction = "receive",
--       message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
--         notification_type = Notification.notification_type.POWER_MANAGEMENT,
--         event = Notification.event.power_management.AC_MAINS_DISCONNECTED,
--       })) }
--     },
--     {
--       channel = "capability",
--       direction = "send",
--       message = mock_sensor:generate_test_message("main", capabilities.powerSource.powerSource.battery())
--     }
--   }
-- )

-- test.register_message_test(
--   "Notification report AC_MAINS_RE_CONNECTED event should be handled power source state dc",
--   {
--     {
--       channel = "zwave",
--       direction = "receive",
--       message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
--         notification_type = Notification.notification_type.POWER_MANAGEMENT,
--         event = Notification.event.power_management.AC_MAINS_RE_CONNECTED,
--       })) }
--     },
--     {
--       channel = "capability",
--       direction = "send",
--       message = mock_sensor:generate_test_message("main", capabilities.powerSource.powerSource.dc())
--     }
--   }
-- )

-- test.register_message_test(
--   "Notification report POWER_HAS_BEEN_APPLIED event should be send battery get",
--   {
--     {
--       channel = "zwave",
--       direction = "receive",
--       message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
--         notification_type = Notification.notification_type.POWER_MANAGEMENT,
--         event = Notification.event.power_management.POWER_HAS_BEEN_APPLIED,
--       })) }
--     },
--     {
--       channel = "zwave",
--       direction = "send",
--       message = zw_test_utils.zwave_test_build_send_command(
--         mock_sensor,
--         Battery:Get({})
--       )
--     }
--   }
-- )

-- test.register_message_test(
--     "Notification report WINDOW_DOOR_IS_OPEN event should be handled contact sensor state open",
--     {
--       {
--         channel = "zwave",
--         direction = "receive",
--         message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
--           notification_type = Notification.notification_type.ACCESS_CONTROL,
--           event = Notification.event.access_control.WINDOW_DOOR_IS_OPEN,
--         })) }
--       },
--       {
--         channel = "capability",
--         direction = "send",
--         message = mock_sensor:generate_test_message("main", capabilities.contactSensor.contact.open())
--       }
--     }
-- )

-- test.register_message_test(
--     "Notification report WINDOW_DOOR_IS_CLOSED event should be handled contact sensor state closed",
--     {
--       {
--         channel = "zwave",
--         direction = "receive",
--         message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
--           notification_type = Notification.notification_type.ACCESS_CONTROL,
--           event = Notification.event.access_control.WINDOW_DOOR_IS_CLOSED,
--         })) }
--       },
--       {
--         channel = "capability",
--         direction = "send",
--         message = mock_sensor:generate_test_message("main", capabilities.contactSensor.contact.closed())
--       }
--     }
-- )

-- test.register_message_test(
--   "Temperature reports should be handled",
--   {
--     {
--       channel = "zwave",
--       direction = "receive",
--       message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
--         sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
--         scale = SensorMultilevel.scale.temperature.CELSIUS,
--         sensor_value = 21.5 }))
--       }
--     },
--     {
--       channel = "capability",
--       direction = "send",
--       message = mock_sensor:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 21.5, unit = 'C' }))
--     },
--   }
-- )

-- test.register_message_test(
--   "Humidity reports should be handled",
--   {
--     {
--       channel = "zwave",
--       direction = "receive",
--       message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
--         sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY,
--         sensor_value = 70 }))
--       }
--     },
--     {
--       channel = "capability",
--       direction = "send",
--       message = mock_sensor:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 70,  }))
--     },
--   }
-- )

-- test.register_message_test(
--   "Sensor multilevel reports dew_point type command should be handled as dew point measurement",
--   {
--     {
--       channel = "zwave",
--       direction = "receive",
--       message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
--         sensor_type = SensorMultilevel.sensor_type.DEW_POINT,
--         sensor_value = 8,
--         scale = 0
--       })) }
--     },
--     {
--       channel = "capability",
--       direction = "send",
--       message = mock_sensor:generate_test_message("main", capabilities.dewPoint.dewpoint({value = 8, unit = "C"}))
--     }
--   }
-- )

-- test.register_coroutine_test(
--   "Three Axis reports should be correctly handled",
--   function()
--     test.socket.zwave:__queue_receive({
--       mock_sensor.id,
--       SensorMultilevel:Report({
--         sensor_type = SensorMultilevel.sensor_type.ACCELERATION_X_AXIS,
--         sensor_value = 1.962,
--         scale = SensorMultilevel.scale.acceleration_x_axis.METERS_PER_SQUARE_SECOND }
--       )
--     })
--     test.socket.zwave:__queue_receive({
--       mock_sensor.id,
--       SensorMultilevel:Report({
--         sensor_type = SensorMultilevel.sensor_type.ACCELERATION_Y_AXIS,
--         sensor_value = 1.962,
--         scale = SensorMultilevel.scale.acceleration_y_axis.METERS_PER_SQUARE_SECOND }
--       )
--     })
--     test.socket.zwave:__queue_receive({
--       mock_sensor.id,
--       SensorMultilevel:Report({
--         sensor_type = SensorMultilevel.sensor_type.ACCELERATION_Z_AXIS,
--         sensor_value = 3.924,
--         scale = SensorMultilevel.scale.acceleration_z_axis.METERS_PER_SQUARE_SECOND }
--       )
--     })
--     test.socket.capability:__expect_send(
--       mock_sensor:generate_test_message("main",
--         capabilities.threeAxis.threeAxis({value = {200, 200, 400}, unit = 'mG'})
--       )
--     )
--   end
-- )


-- test.register_message_test(
--     "Notification report type WEATHER_ALARM event STATE_IDLE should be handled mold healt concern state good",
--     {
--       {
--         channel = "zwave",
--         direction = "receive",
--         message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
--           notification_type = Notification.notification_type.WEATHER_ALARM,
--           event = Notification.event.weather_alarm.STATE_IDLE,
--         }))}
--       },
--       {
--         channel = "capability",
--         direction = "send",
--         message = mock_sensor:generate_test_message("main", capabilities.moldHealthConcern.moldHealthConcern.good())
--       }
--     }
-- )

-- test.register_message_test(
--     "Notification report type WEATHER_ALARM event MOISTURE_ALARM should be handled mold healt concern state moderate",
--     {
--       {
--         channel = "zwave",
--         direction = "receive",
--         message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
--           notification_type = Notification.notification_type.WEATHER_ALARM,
--           event = Notification.event.weather_alarm.MOISTURE_ALARM,
--         }))}
--       },
--       {
--         channel = "capability",
--         direction = "send",
--         message = mock_sensor:generate_test_message("main", capabilities.moldHealthConcern.moldHealthConcern.good())
--       }
--     }
-- )

test.run_registered_tests()