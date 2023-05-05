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
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
local SensorAlarm = (require "st.zwave.CommandClass.SensorAlarm")({ version = 1 })
local SensorBinaryv1 = (require "st.zwave.CommandClass.SensorBinary")({ version = 1 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })

local zwave_sensor_profile = {
  components = {
    main = {
      capabilities = {
        [capabilities.contactSensor.ID] = { id = capabilities.contactSensor.ID },
        [capabilities.motionSensor.ID] = { id = capabilities.motionSensor.ID },
        [capabilities.waterSensor.ID] = { id = capabilities.waterSensor.ID },
        [capabilities.relativeHumidityMeasurement.ID] = { id = capabilities.relativeHumidityMeasurement.ID },
        [capabilities.battery.ID] = { id = capabilities.battery.ID },
        [capabilities.tamperAlert.ID] = { id = capabilities.tamperAlert.ID },
        [capabilities.illuminanceMeasurement.ID] = { id = capabilities.illuminanceMeasurement.ID },
        [capabilities.moldHealthConcern.ID] = { id = capabilities.moldHealthConcern.ID },
        [capabilities.dewPoint.ID] = { id = capabilities.dewPoint.ID },
        [capabilities.refresh.ID] = { id = capabilities.refresh.ID },
      },
      id = "main"
    }
  }
}

local zwave_motion_sensor_profile = {
  components = {
    main = {
      capabilities = {
        [capabilities.motionSensor.ID] = { id = capabilities.motionSensor.ID },
      },
      id = "main"
    }
  }
}

local zwave_water_sensor_profile = {
  components = {
    main = {
      capabilities = {
        [capabilities.waterSensor.ID] = { id = capabilities.waterSensor.ID },
      },
      id = "main"
    }
  }
}

local zwave_contact_sensor_profile = {
  components = {
    main = {
      capabilities = {
        [capabilities.contactSensor.ID] = { id = capabilities.contactSensor.ID },
      },
      id = "main"
    }
  }
}
-- supported comand classes
local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = zw.SENSOR_BINARY},
      {value = zw.BASIC},
      {value = zw.SENSOR_ALARM},
      {value = zw.SENSOR_MULTILEVEL},
      {value = zw.NOTIFICATION}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = zwave_sensor_profile,
    zwave_endpoints = sensor_endpoints
  }
)

local mock_motion_device = test.mock_device.build_test_zwave_device(
  {
    profile = zwave_motion_sensor_profile,
    zwave_endpoints = sensor_endpoints
  }
)

local mock_water_device = test.mock_device.build_test_zwave_device(
  {
    profile = zwave_water_sensor_profile,
    zwave_endpoints = sensor_endpoints
  }
)

local mock_contact_device = test.mock_device.build_test_zwave_device(
  {
    profile = zwave_contact_sensor_profile,
    zwave_endpoints = sensor_endpoints
  }
)

local function  test_init()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_motion_device)
  test.mock_device.add_test_device(mock_water_device)
  test.mock_device.add_test_device(mock_contact_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Battery report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Battery:Report({ battery_level = 0x63 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.battery.battery(99))
      }
    }
)

test.register_message_test(
  "Refresh should generate the correct commands",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "added" },
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    -- },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.waterSensor.water.dry())
    -- },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.moldHealthConcern.moldHealthConcern.good())
    -- },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.closed())
    -- },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    -- },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Battery:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY, scale = SensorMultilevel.scale.relative_humidity.PERCENTAGE})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.LUMINANCE, scale = SensorMultilevel.scale.luminance.LUX})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SensorBinary:Get({sensor_type = SensorBinary.sensor_type.DOOR_WINDOW})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SensorBinary:Get({sensor_type = SensorBinary.sensor_type.MOTION})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SensorBinary:Get({sensor_type = SensorBinary.sensor_type.WATER})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.DEW_POINT})
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
    "Basic report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0xFF })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.waterSensor.water.wet())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "Sensor Binary report (water) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorBinary:Report({
          sensor_type = SensorBinary.sensor_type.WATER,
          sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "Sensor Binary report (motion) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorBinary:Report({
          sensor_type = SensorBinary.sensor_type.MOTION,
          sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "Sensor Binary report (contact) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorBinary:Report({
          sensor_type = SensorBinary.sensor_type.DOOR_WINDOW,
          sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.open())
      }
    }
)

test.register_message_test(
    "Basic Set (contact) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({
          value = 1
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.open())
      }
    }
)

test.register_message_test(
    "Basic Set (contact) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_motion_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({
          value = 1
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_motion_device:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "Sensor Binary report (v1) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorBinaryv1:Report({
          sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.waterSensor.water.wet())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "Sensor Alarm report (general) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorAlarm:Report({
          sensor_type = SensorAlarm.sensor_type.GENERAL_PURPOSE_ALARM,
          sensor_state = SensorAlarm.sensor_state.ALARM
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "Sensor Alarm report (leak) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorAlarm:Report({
          sensor_type = SensorAlarm.sensor_type.WATER_LEAK_ALARM,
          sensor_state = SensorAlarm.sensor_state.ALARM
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "Humidity reports should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
          sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY,
          scale = SensorMultilevel.scale.relative_humidity.PERCENTAGE,
          sensor_value = 21.5 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 22 }))
      }
    }
)

test.register_message_test(
    "Illuminance reports should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
          sensor_type = SensorMultilevel.sensor_type.LUMINANCE,
          scale = SensorMultilevel.scale.luminance.LUX,
          sensor_value = 400 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance({ value = 400, unit = "lux" }))
      }
    }
)

test.register_message_test(
    "Notification report (leak) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.WATER,
          event = Notification.event.water.LEAK_DETECTED
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "Notification report (motion) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HOME_SECURITY,
          event = Notification.event.home_security.MOTION_DETECTION
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "Notification report (contact) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_contact_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HOME_SECURITY,
          event = Notification.event.home_security.INTRUSION
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_contact_device:generate_test_message("main", capabilities.contactSensor.contact.open())
      }
    }
)

test.register_message_test(
    "Notification report (home security idle) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HOME_SECURITY,
          event = Notification.event.home_security.STATE_IDLE
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      }
    }
)

test.register_message_test(
    "Notification report (water idle) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.WATER,
          event = Notification.event.water.STATE_IDLE
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "Notification report (tamper) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HOME_SECURITY,
          event = Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "Basic report (motion sensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_motion_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0xFF })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_motion_device:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "Basic report (water sensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_water_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0xFF })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_water_device:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "Basic report (contact sensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_contact_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0xFF })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_contact_device:generate_test_message("main", capabilities.contactSensor.contact.open())
      }
    }
)

test.register_message_test(
    "Notification report (mold detection) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.WEATHER_ALARM,
          event = Notification.event.weather_alarm.MOISTURE_ALARM
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.moldHealthConcern.moldHealthConcern.unhealthy())
      }
    }
)

test.register_message_test(
    "Notification report (no mold detection) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.WEATHER_ALARM,
          event = Notification.event.weather_alarm.STATE_IDLE
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.moldHealthConcern.moldHealthConcern.good())
      }
    }
)

test.register_message_test(
  "Sensor multilevel reports dew_point type command should be handled as dew point measurement",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.DEW_POINT,
        sensor_value = 8,
        scale = 0
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.dewPoint.dewpoint({value = 8, unit = "C"}))
    }
  }
)

test.run_registered_tests()
