-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

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
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = zw.NOTIFICATION},
      {value = zw.SENSOR_MULTILEVEL},
    }
  }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-door-window-sensor-8.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0002,
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
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.moldHealthConcern.supportedMoldValues({"good", "unhealthy"}))
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
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Device init lifecycle event",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_sensor.id, "init" })
  end,
  {
    min_api_version = 17
  }
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
  },
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Notification report TAMPERING_PRODUCT_COVER_REMOVED event should be handled as tamperAlert detected",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.HOME_SECURITY,
        event = Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED,
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
    }
  },
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Battery report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Battery:Report({ battery_level = 0x63 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.battery.battery(99))
    }
  },
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Notification report AC_MAINS_DISCONNECTED event should be handled power source state battery",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.POWER_MANAGEMENT,
        event = Notification.event.power_management.AC_MAINS_DISCONNECTED,
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.powerSource.powerSource.battery())
    }
  },
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Notification report AC_MAINS_RE_CONNECTED event should be handled power source state dc",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.POWER_MANAGEMENT,
        event = Notification.event.power_management.AC_MAINS_RE_CONNECTED,
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.powerSource.powerSource.dc())
    }
  },
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Notification report POWER_HAS_BEEN_APPLIED event should be send battery get",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.POWER_MANAGEMENT,
        event = Notification.event.power_management.POWER_HAS_BEEN_APPLIED,
      })) }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        Battery:Get({})
      )
    }
  },
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Notification report WINDOW_DOOR_IS_OPEN event should be handled contact sensor state open",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = Notification.event.access_control.WINDOW_DOOR_IS_OPEN,
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.contactSensor.contact.open())
    }
  },
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Notification report WINDOW_DOOR_IS_CLOSED event should be handled contact sensor state closed",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = Notification.event.access_control.WINDOW_DOOR_IS_CLOSED,
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.contactSensor.contact.closed())
    }
  },
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Temperature reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = SensorMultilevel.scale.temperature.CELSIUS,
        sensor_value = 21.5 }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 21.5, unit = 'C' }))
    },
  },
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Humidity reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY,
        scale = SensorMultilevel.scale.relative_humidity.PERCENTAGE,
        sensor_value = 70 }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 70 }))
    },
  },
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Sensor multilevel reports dew_point type command should be handled as dew point measurement",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.DEW_POINT,
        sensor_value = 8,
        scale = 0
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.dewPoint.dewpoint({value = 8, unit = "C"}))
    }
  },
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Three Axis reports are converted, clamped and combined",
  function()
    local function receive_axis(sensor_type, value)
      test.socket.zwave:__queue_receive({
        mock_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(
          SensorMultilevel:Report({
            sensor_type = sensor_type,
            sensor_value = value,
            scale = 0
          })
        )
      })
    end

    local function expect_vector(x, y, z)
      test.socket.capability:__expect_send(
        mock_sensor:generate_test_message(
          "main",
          capabilities.threeAxis.threeAxis({
            value = { x, y, z },
            unit = "mG"
          })
        )
      )
    end

    -- X: 9,81 m/s² -> 1000 mG. Noch kein vollständiger Vektor.
    receive_axis(SensorMultilevel.sensor_type.ACCELERATION_X_AXIS, 9.81)

    -- Y: -9,81 m/s² -> -1000 mG. Noch kein vollständiger Vektor.
    receive_axis(SensorMultilevel.sensor_type.ACCELERATION_Y_AXIS, -9.81)

    -- Z: 120 m/s² -> über 10000 mG -> auf 10000 begrenzt.
    receive_axis(SensorMultilevel.sensor_type.ACCELERATION_Z_AXIS, 120)
    expect_vector(1000, -1000, 10000)

    -- Ein neuer X-Report sendet einen Vektor mit den zuletzt bekannten Y/Z.
    receive_axis(SensorMultilevel.sensor_type.ACCELERATION_X_AXIS, -120)
    expect_vector(-10000, -1000, 10000)
  end,
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Notification report type WEATHER_ALARM event STATE_IDLE should be handled mold healt concern state good",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.WEATHER_ALARM,
        event = Notification.event.weather_alarm.STATE_IDLE,
      }))}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.moldHealthConcern.moldHealthConcern.good())
    }
  },
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Notification report type WEATHER_ALARM event MOISTURE_ALARM should be handled mold healt concern state unhealthy",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.WEATHER_ALARM,
        event = Notification.event.weather_alarm.MOISTURE_ALARM,
      }))}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.moldHealthConcern.moldHealthConcern.unhealthy())
    }
  },
  {
    min_api_version = 17
  }
)

test.run_registered_tests()
