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
local SensorAlarm = (require "st.zwave.CommandClass.SensorAlarm")({ version = 1 })
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.SENSOR_ALARM},
      {value = zw.SENSOR_BINARY},
      {value = zw.SENSOR_MULTILEVEL},
      {value = zw.NOTIFICATION}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("water-battery-temperature.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0084,
  zwave_product_type = 0x0063,
  zwave_product_id = 0x010C,
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Device should be refreshed after configuration",
  function ()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.WATER })
      ))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE, scale = SensorMultilevel.scale.temperature.CELSIUS })
      ))
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_message_test(
  "Notification report LEAK_DETECTED_LOCATION_PROVIDED event should be handled water sensor state wet",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.WATER,
        event = Notification.event.water.LEAK_DETECTED_LOCATION_PROVIDED,
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
  "Notification report LEAK_DETECTED event should be handled water sensor state wet",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.WATER,
        event = Notification.event.water.LEAK_DETECTED,
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
  "Notification report STATE_IDLE event should be handled water sensor state dry",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.WATER,
        event = Notification.event.water.STATE_IDLE,
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
  "Notification report UNKNOWN_EVENT_STATE event should be handled water sensor state dry",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.WATER,
        event = Notification.event.water.UNKNOWN_EVENT_STATE,
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
  "SensorAlarm report ALARM should be handled as waterSensor wet",
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
  "SensorAlarm report ALARM should be handled as waterSensor dry",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorAlarm:Report({
        sensor_type = SensorAlarm.sensor_type.WATER_LEAK_ALARM,
        sensor_state = SensorAlarm.sensor_state.NO_ALARM
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
  "Temperature reports should be handled (unit: C)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = SensorMultilevel.scale.temperature.CELSIUS,
        sensor_value = 21 }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 21, unit = 'C' }))
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
        sensor_value = 37 }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 37, unit = 'F' }))
    }
  }
)

test.register_message_test(
  "Basic SET 0x00 should be handled as water dry",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({value=0x00})) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.waterSensor.water.dry())
    }
  }
)

test.register_message_test(
  "Basic SET 0xFF should be handled as water wet",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({value=0xFF})) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.waterSensor.water.wet())
    }
  }
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

test.run_registered_tests()
