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

local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
local SensorAlarm = (require "st.zwave.CommandClass.SensorAlarm")({ version = 1 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
local Association = (require "st.zwave.CommandClass.Association")({ version=2 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 2 })

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = zw.SENSOR_MULTILEVEL},
      {value = zw.SENSOR_BINARY},
      {value = zw.SENSOR_ALARM},
      {value = zw.NOTIFICATION},
      {value = zw.WAKEUP}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("motion-battery-temperature-illuminance-acceleration.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x010F,
  zwave_product_type = 0x0800,
  zwave_product_id = 0x1001,
})

local function  test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "doConfigure lifecycle event should configure and refresh device",
  function ()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })

    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      Configuration:Set({parameter_number=24, size=1, configuration_value=4})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      Configuration:Set({parameter_number=60, size=1, configuration_value=5})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      Association:Set({grouping_identifier = 3, node_ids = {}})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      WakeUp:IntervalSet({node_id = 0x00, seconds = 7200})
    ))

    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      SensorBinary:Get({sensor_type = SensorBinary.sensor_type.MOTION})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.LUMINANCE, scale = SensorMultilevel.scale.luminance.LUX})
    ))
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

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
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
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
      message = mock_device:generate_test_message("main", capabilities.accelerationSensor.acceleration.active())
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
          sensor_state = SensorAlarm.sensor_state.NO_ALARM
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.accelerationSensor.acceleration.inactive())
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
          sensor_state = 50
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.accelerationSensor.acceleration.active())
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
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    }
  }
)

test.register_message_test(
  "Basic report (motion sensor) should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0xFF })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    }
  }
)

test.register_message_test(
  "Temperature reports should be handled (unit: C)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = SensorMultilevel.scale.temperature.CELSIUS,
        sensor_value = 21.5 }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 21.5, unit = 'C' }))
    }
  }
)

test.register_message_test(
  "Temperature reports should be handled (unit: F)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = SensorMultilevel.scale.temperature.FAHRENHEIT,
        sensor_value = 70.7 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 70.7, unit = 'F' }))
    }
  }
)

test.run_registered_tests()
