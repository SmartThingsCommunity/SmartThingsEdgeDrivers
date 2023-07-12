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
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 2 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
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

local PARAMETERS = {
  { name = 'motionDelayTime',        parameter_number = 3,  size = 2, configuration_value = 120 },
  { name = 'motionSensitivity',      parameter_number = 4,  size = 1, configuration_value = 2 },
  { name = 'motionReportType',       parameter_number = 5,  size = 1, configuration_value = 1 },
  { name = 'lowBatteryThreshold',    parameter_number = 14, size = 1, configuration_value = 10 },
  { name = 'toggleThresholdReports', parameter_number = 15, size = 1, configuration_value = 1 },
  { name = 'tempThreshold',          parameter_number = 16, size = 1, configuration_value = 20 },
  { name = 'luxThreshold',           parameter_number = 17, size = 2, configuration_value = 20 },
  { name = 'checkTimeThreshold',     parameter_number = 18, size = 2, configuration_value = 70 },
  { name = 'sensorLimitControl',     parameter_number = 19, size = 1, configuration_value = 7 },
  { name = 'tempUpperLimit',         parameter_number = 20, size = 2, configuration_value = 300 },
  { name = 'tempLowerLimit',         parameter_number = 21, size = 2, configuration_value = -200 },
  { name = 'luxUpperLimit',          parameter_number = 22, size = 2, configuration_value = 2000 },
  { name = 'luxLowerLimit',          parameter_number = 23, size = 2, configuration_value = 2000 },
  { name = 'tempScale',              parameter_number = 24, size = 1, configuration_value = 1 },
  { name = 'automaticIntervalTime',  parameter_number = 25, size = 2, configuration_value = 30 }
}

local PARAMETERS_US = {
  { name = 'motionDelayTime',        parameter_number = 3,  size = 2, configuration_value = 120 },
  { name = 'motionSensitivity',      parameter_number = 4,  size = 1, configuration_value = 2 },
  { name = 'motionReportType',       parameter_number = 5,  size = 1, configuration_value = 1 },
  { name = 'lowBatteryThreshold',    parameter_number = 14, size = 1, configuration_value = 10 },
  { name = 'toggleThresholdReports', parameter_number = 15, size = 1, configuration_value = 1 },
  { name = 'tempThreshold',          parameter_number = 16, size = 1, configuration_value = 20 },
  { name = 'luxThreshold',           parameter_number = 17, size = 2, configuration_value = 20 },
  { name = 'checkTimeThreshold',     parameter_number = 18, size = 2, configuration_value = 70 },
  { name = 'sensorLimitControl',     parameter_number = 19, size = 1, configuration_value = 7 },
  { name = 'tempUpperLimit',         parameter_number = 20, size = 2, configuration_value = 1420 },
  { name = 'tempLowerLimit',         parameter_number = 21, size = 2, configuration_value = -200 },
  { name = 'luxUpperLimit',          parameter_number = 22, size = 2, configuration_value = 2000 },
  { name = 'luxLowerLimit',          parameter_number = 23, size = 2, configuration_value = 2000 },
  { name = 'tempScale',              parameter_number = 24, size = 1, configuration_value = 0 },
  { name = 'automaticIntervalTime',  parameter_number = 25, size = 2, configuration_value = 30 }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("aeotec-trisensor-8-eu.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x0371,
    zwave_product_type = 0x0002,
    zwave_product_id = 0x002D,
})

local mock_sensor_us = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-trisensor-8-us.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0102,
  zwave_product_id = 0x002D
})

local function test_init()
  test.mock_device.add_test_device(mock_sensor)
  test.mock_device.add_test_device(mock_sensor_us)
end

local function gen_info_change(params, mock_device)
  local preferences = {}
  for _, param in ipairs(params) do
    preferences[param.name] = param.configuration_value
  end
  return mock_device:generate_info_changed({ preferences = preferences })
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "doConfigure lifecycle event should generate the correct commands",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_sensor_us.id, "doConfigure" })

    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_sensor_us,
      Configuration:Set({ parameter_number = 24, configuration_value = 1, size = 1 })
    ))

    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_sensor_us,
      Notification:Get({ notification_type = Notification.notification_type.HOME_SECURITY })
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_sensor_us,
      Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_sensor_us,
      SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.TEMPERATURE })
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_sensor_us,
      SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.LUMINANCE })
    ))

    mock_sensor_us:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "doConfigure lifecycle event should generate the correct commands",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_sensor.id, "doConfigure" })

    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_sensor,
      Notification:Get({ notification_type = Notification.notification_type.HOME_SECURITY })
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_sensor,
      Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_sensor,
      SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.TEMPERATURE })
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_sensor,
      SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.LUMINANCE })
    ))

    mock_sensor:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Wakeup notification should generate the correct commands",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.zwave:__queue_receive(
      {
          mock_sensor.id,
          WakeUp:Notification({})
      }
    )
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        Notification:Get({ notification_type = Notification.notification_type.HOME_SECURITY })
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        Battery:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.TEMPERATURE })
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.LUMINANCE})
    ))
  end
)

test.register_coroutine_test(
  "Configuration value should be updated and device refreshed, when wakeup notification received (EU)",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle():__queue_receive(gen_info_change(PARAMETERS, mock_sensor))

    for _, param in pairs(PARAMETERS) do
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        Configuration:Set({ parameter_number = param.parameter_number, size = param.size, configuration_value = param.configuration_value })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        Configuration:Get({ parameter_number = param.parameter_number })
      ))
    end
  end
)

test.register_coroutine_test(
  "Configuration value should be updated and device refreshed, when wakeup notification received (US)",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle():__queue_receive(gen_info_change(PARAMETERS_US, mock_sensor_us))

    for _, param in pairs(PARAMETERS_US) do
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor_us,
        Configuration:Set({ parameter_number = param.parameter_number, size = param.size,
          configuration_value = param.configuration_value })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor_us,
        Configuration:Get({ parameter_number = param.parameter_number })
      ))
    end
  end
)

test.register_message_test(
  "Notification reports about motion should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.HOME_SECURITY,
        event = Notification.event.home_security.STATE_IDLE
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.HOME_SECURITY,
        event = Notification.event.home_security.MOTION_DETECTION
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
  "Battery report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(Battery:Report({ battery_level = 0x63 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.battery.battery(99))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(Battery:Report({ battery_level = 0x32 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.battery.battery(50))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(Battery:Report({ battery_level = 0x00 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.battery.battery(0))
    }
  }
)

test.register_message_test(
  "Temperature reports should be handled (unit: C)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
          sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
          scale = SensorMultilevel.scale.temperature.CELSIUS,
          sensor_value = 50
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main",
        capabilities.temperatureMeasurement.temperature({ value = 50, unit = 'C' }))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
          sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
          scale = SensorMultilevel.scale.temperature.CELSIUS,
          sensor_value = 21.5
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main",
        capabilities.temperatureMeasurement.temperature({ value = 21.5, unit = 'C' }))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
          sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
          scale = SensorMultilevel.scale.temperature.CELSIUS,
          sensor_value = 0
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main",
        capabilities.temperatureMeasurement.temperature({ value = 0, unit = 'C' }))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
          sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
          scale = SensorMultilevel.scale.temperature.CELSIUS,
          sensor_value = -10
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main",
        capabilities.temperatureMeasurement.temperature({ value = -10, unit = 'C' }))
    }
  }
)

test.register_message_test(
  "Temperature reports should be handled (unit: F)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor_us.id,
        zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
          sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
          scale = SensorMultilevel.scale.temperature.FAHRENHEIT,
          sensor_value = 122
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor_us:generate_test_message("main",
        capabilities.temperatureMeasurement.temperature({ value = 122, unit = 'F' }))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor_us.id,
        zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
          sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
          scale = SensorMultilevel.scale.temperature.FAHRENHEIT,
          sensor_value = 70.5
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor_us:generate_test_message("main",
        capabilities.temperatureMeasurement.temperature({ value = 70.5, unit = 'F' }))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor_us.id,
        zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
          sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
          scale = SensorMultilevel.scale.temperature.FAHRENHEIT,
          sensor_value = 14
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor_us:generate_test_message("main",
        capabilities.temperatureMeasurement.temperature({ value = 14, unit = 'F' }))
    }
  }
)

test.register_message_test(
  "Illuminance reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.LUMINANCE,
        scale = SensorMultilevel.scale.luminance.LUX,
        sensor_value = 10000
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main",
        capabilities.illuminanceMeasurement.illuminance({ value = 10000, unit = "lux" }))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.LUMINANCE,
        scale = SensorMultilevel.scale.luminance.LUX,
        sensor_value = 400
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main",
        capabilities.illuminanceMeasurement.illuminance({ value = 400, unit = "lux" }))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.LUMINANCE,
        scale = SensorMultilevel.scale.luminance.LUX,
        sensor_value = 0
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main",
        capabilities.illuminanceMeasurement.illuminance({ value = 0, unit = "lux" }))
    }
  }
)

test.run_registered_tests()
