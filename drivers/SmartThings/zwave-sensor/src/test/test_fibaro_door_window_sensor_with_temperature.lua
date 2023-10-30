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

local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 2 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 2 })
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })

local FIBARO_DOOR_WINDOW_SENSOR_WITH_TEMPERATURE_MANUFACTURER_ID = 0x010F
local FIBARO_DOOR_WINDOW_SENSOR_WITH_TEMPERATURE_PRODUCT_TYPE = 0x0701
local FIBARO_DOOR_WINDOW_SENSOR_WITH_TEMPERATURE_PRODUCT_ID = 0x2001

local WAKEUP_INTERVAL = 21600 --seconds

local fibaro_door_window_sensor_endpoints = {
  {
    command_classes = {
      { value = zw.ASSOCIATION },
      { value = zw.BATTERY },
      { value = zw.NOTIFICATION },
      { value = zw.SENSOR_BINARY },
      { value = zw.SENSOR_MULTILEVEL },
      { value = zw.WAKE_UP }
    }
  }
}

local mock_fibaro_door_window_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("fibaro-door-window-sensor-temperature.yml"),
  zwave_endpoints = fibaro_door_window_sensor_endpoints,
  zwave_manufacturer_id = FIBARO_DOOR_WINDOW_SENSOR_WITH_TEMPERATURE_MANUFACTURER_ID,
  zwave_product_type = FIBARO_DOOR_WINDOW_SENSOR_WITH_TEMPERATURE_PRODUCT_TYPE,
  zwave_product_id = FIBARO_DOOR_WINDOW_SENSOR_WITH_TEMPERATURE_PRODUCT_ID
})

test.mock_device.add_test_device(mock_fibaro_door_window_sensor)

local function test_init()
    test.mock_device.add_test_device(mock_fibaro_door_window_sensor)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Device should be polled with refresh right after inclusion",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_fibaro_door_window_sensor.id, "added" }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Battery:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        SensorBinary:Get({})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
    "Device should be configured",
    function ()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_fibaro_door_window_sensor.id, "doConfigure" })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor,
          WakeUp:IntervalSet({node_id = 0x00, seconds = WAKEUP_INTERVAL})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor,
          Battery:Get({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        SensorBinary:Get({})
      ))
      mock_fibaro_door_window_sensor:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_message_test(
 "Battery report should be handled",
 {
   {
       channel = "zwave",
       direction = "receive",
       message = { mock_fibaro_door_window_sensor.id, zw_test_utils.zwave_test_build_receive_command(Battery:Report({ battery_level = 0x63 })) }
   },
   {
       channel = "capability",
       direction = "send",
       message = mock_fibaro_door_window_sensor:generate_test_message("main", capabilities.battery.battery(99))
   }
 }
)

test.register_message_test(
 "Notification report (tamper detected) should be handled",
 {
   {
     channel = "zwave",
     direction = "receive",
     message = { mock_fibaro_door_window_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
       notification_type =  Notification.notification_type.HOME_SECURITY,
       event = Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED
     }))}
   },
   {
     channel = "capability",
     direction = "send",
     message = mock_fibaro_door_window_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
   }
 }
)

test.register_message_test(
 "Notification report (tamper clear) should be handled",
 {
   {
     channel = "zwave",
     direction = "receive",
     message = { mock_fibaro_door_window_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
       notification_type =  Notification.notification_type.HOME_SECURITY,
       event = Notification.event.home_security.STATE_IDLE
     }))}
   },
   {
     channel = "capability",
     direction = "send",
     message = mock_fibaro_door_window_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
   }
 }
)


test.register_message_test(
 "Notification report (contact / open) should be handled",
 {
   {
     channel = "zwave",
     direction = "receive",
     message = { mock_fibaro_door_window_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
       notification_type =  Notification.notification_type.ACCESS_CONTROL,
       event = Notification.event.access_control.WINDOW_DOOR_IS_OPEN
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
 "Notification report (contact / closed) should be handled",
 {
   {
     channel = "zwave",
     direction = "receive",
     message = { mock_fibaro_door_window_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
       notification_type =  Notification.notification_type.ACCESS_CONTROL,
       event = Notification.event.access_control.WINDOW_DOOR_IS_CLOSED
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
  "Temperature reports should be handled (unit: C)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_fibaro_door_window_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = SensorMultilevel.scale.temperature.CELSIUS,
        sensor_value = 21.5 }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_door_window_sensor:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 21.5, unit = 'C' }))
    }
  }
)

test.register_message_test(
  "Temperature reports should be handled (unit: F)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_fibaro_door_window_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = SensorMultilevel.scale.temperature.FAHRENHEIT,
        sensor_value = 70.7 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_door_window_sensor:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 70.7, unit = 'F' }))
    }
  }
)

test.register_coroutine_test(
  "Device should be configured after changing device settings",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle():__queue_receive({mock_fibaro_door_window_sensor.id, "init"})
    test.timer.__create_and_queue_test_time_advance_timer(11, "oneshot")
    local _preferences = {}
    _preferences.alarmStatus = 1 -- "Door/window opened"
    test.socket.device_lifecycle():__queue_receive(mock_fibaro_door_window_sensor:generate_info_changed({ preferences = _preferences }))
    test.wait_for_events()
    test.socket.zwave:__queue_receive(
      {
        mock_fibaro_door_window_sensor.id,
        WakeUp:Notification({})
      }
    )
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      WakeUp:IntervalGet({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorBinary:Get({})
    ))

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Set({
          parameter_number = 2,
          configuration_value = 1,
          size = 1
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({ parameter_number = 2 })
      )
    )

    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_fibaro_door_window_sensor.id,
      Configuration:Report({ parameter_number = 2, configuration_value = 1 })
    })

    test.mock_time.advance_time(1)

    _preferences = {}
    _preferences.visualLedIndications = 4 --"Indication of device tampering"
    test.socket.device_lifecycle():__queue_receive(mock_fibaro_door_window_sensor:generate_info_changed({ preferences = _preferences }))
    test.wait_for_events()
    test.socket.zwave:__queue_receive(
      {
        mock_fibaro_door_window_sensor.id,
        WakeUp:Notification({})
      }
    )
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorBinary:Get({})
    ))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Set({
          parameter_number = 3,
          configuration_value = 4,
          size = 1
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({ parameter_number = 3 })
      )
    )

    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_fibaro_door_window_sensor.id,
      Configuration:Report({ parameter_number = 3, configuration_value = 4 })
    })

    test.mock_time.advance_time(1)
    _preferences = {}
    _preferences.delayOfTamperAlarmCancel = 5
    test.socket.device_lifecycle():__queue_receive(mock_fibaro_door_window_sensor:generate_info_changed({ preferences = _preferences }))
    test.wait_for_events()
        test.socket.zwave:__queue_receive(
      {
        mock_fibaro_door_window_sensor.id,
        WakeUp:Notification({})
      }
    )
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorBinary:Get({})
    ))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Set({
          parameter_number = 30,
          configuration_value = 5,
          size = 2
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({ parameter_number = 30 })
      )
    )

    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_fibaro_door_window_sensor.id,
      Configuration:Report({ parameter_number = 30, configuration_value = 5 })
    })

    test.mock_time.advance_time(1)

    _preferences = {}
    _preferences.reportTamperAlarmCancel = 1
    test.socket.device_lifecycle():__queue_receive(mock_fibaro_door_window_sensor:generate_info_changed({ preferences = _preferences }))
    test.wait_for_events()
    test.socket.zwave:__queue_receive(
      {
        mock_fibaro_door_window_sensor.id,
        WakeUp:Notification({})
      }
    )
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorBinary:Get({})
    ))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Set({
          parameter_number = 31,
          configuration_value = 1,
          size = 1
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({ parameter_number = 31 })
      )
    )

    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_fibaro_door_window_sensor.id,
      Configuration:Report({ parameter_number = 31, configuration_value = 1 })
    })

    test.mock_time.advance_time(1)

    _preferences = {}
    _preferences.tempMeasurementInterval = 300
    test.socket.device_lifecycle():__queue_receive(mock_fibaro_door_window_sensor:generate_info_changed({ preferences = _preferences }))
    test.wait_for_events()
    test.socket.zwave:__queue_receive(
      {
        mock_fibaro_door_window_sensor.id,
        WakeUp:Notification({})
      }
    )
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorBinary:Get({})
    ))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Set({
          parameter_number = 50,
          configuration_value = 300,
          size = 2
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({ parameter_number = 50 })
      )
    )

    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_fibaro_door_window_sensor.id,
      Configuration:Report({ parameter_number = 50, configuration_value = 300 })
    })

    test.mock_time.advance_time(1)

    _preferences = {}
    _preferences.tempReportsThreshold = 10
    test.socket.device_lifecycle():__queue_receive(mock_fibaro_door_window_sensor:generate_info_changed({ preferences = _preferences }))
    test.wait_for_events()
    test.socket.zwave:__queue_receive(
      {
        mock_fibaro_door_window_sensor.id,
        WakeUp:Notification({})
      }
    )
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorBinary:Get({})
    ))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Set({
          parameter_number = 51,
          configuration_value = 10,
          size = 2
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({ parameter_number = 51 })
      )
    )

    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_fibaro_door_window_sensor.id,
      Configuration:Report({ parameter_number = 51, configuration_value = 10 })
    })

    test.mock_time.advance_time(1)

    _preferences = {}
    _preferences.intervalOfTempReports = 0
    test.socket.device_lifecycle():__queue_receive(mock_fibaro_door_window_sensor:generate_info_changed({ preferences = _preferences }))
    test.wait_for_events()
    test.socket.zwave:__queue_receive(
      {
        mock_fibaro_door_window_sensor.id,
        WakeUp:Notification({})
      }
    )
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorBinary:Get({})
    ))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Set({
          parameter_number = 52,
          configuration_value = 0,
          size = 2
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({ parameter_number = 52 })
      )
    )

    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_fibaro_door_window_sensor.id,
      Configuration:Report({ parameter_number = 52, configuration_value = 0 })
    })

    test.mock_time.advance_time(1)

    _preferences = {}
    _preferences.temperatureOffset = 0
    test.socket.device_lifecycle():__queue_receive(mock_fibaro_door_window_sensor:generate_info_changed({ preferences = _preferences }))
    test.wait_for_events()
    test.socket.zwave:__queue_receive(
      {
        mock_fibaro_door_window_sensor.id,
        WakeUp:Notification({})
      }
    )
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorBinary:Get({})
    ))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Set({
          parameter_number = 53,
          configuration_value = 0,
          size = 4
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({ parameter_number = 53 })
      )
    )

    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_fibaro_door_window_sensor.id,
      Configuration:Report({ parameter_number = 53, configuration_value = 0 })
    })

    test.mock_time.advance_time(1)

    _preferences = {}
    _preferences.temperatureAlarmReports = 0
    test.socket.device_lifecycle():__queue_receive(mock_fibaro_door_window_sensor:generate_info_changed({ preferences = _preferences }))
    test.wait_for_events()
    test.socket.zwave:__queue_receive(
      {
        mock_fibaro_door_window_sensor.id,
        WakeUp:Notification({})
      }
    )
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorBinary:Get({})
    ))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Set({
          parameter_number = 54,
          configuration_value = 0,
          size = 1
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({ parameter_number = 54 })
      )
    )

    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_fibaro_door_window_sensor.id,
      Configuration:Report({ parameter_number = 54, configuration_value = 0 })
    })

    test.mock_time.advance_time(1)

    _preferences = {}
    _preferences.highTempThreshold = 540
    test.socket.device_lifecycle():__queue_receive(mock_fibaro_door_window_sensor:generate_info_changed({ preferences = _preferences }))
    test.wait_for_events()
    test.socket.zwave:__queue_receive(
      {
        mock_fibaro_door_window_sensor.id,
        WakeUp:Notification({})
      }
    )
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorBinary:Get({})
    ))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Set({
          parameter_number = 55,
          configuration_value = 540,
          size = 2
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({ parameter_number = 55 })
      )
    )

    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_fibaro_door_window_sensor.id,
      Configuration:Report({ parameter_number = 55, configuration_value = 540 })
    })

    test.mock_time.advance_time(1)

    _preferences = {}
    _preferences.lowTempThreshold = 40
    test.socket.device_lifecycle():__queue_receive(mock_fibaro_door_window_sensor:generate_info_changed({ preferences = _preferences }))
    test.wait_for_events()
    test.socket.zwave:__queue_receive(
      {
        mock_fibaro_door_window_sensor.id,
        WakeUp:Notification({})
      }
    )
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_fibaro_door_window_sensor,
      SensorBinary:Get({})
    ))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Set({
          parameter_number = 56,
          configuration_value = 40,
          size = 2
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor,
        Configuration:Get({ parameter_number = 56 })
      )
    )

    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_fibaro_door_window_sensor.id,
      Configuration:Report({ parameter_number = 56, configuration_value = 40 })
    })
  end
)

test.run_registered_tests()
