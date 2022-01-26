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
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local SensorAlarm = (require "st.zwave.CommandClass.SensorAlarm")({ version = 1 })
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.SENSOR_ALARM},
      {value = zw.SENSOR_BINARY},
      {value = zw.SENSOR_MULTILEVEL}
    }
  }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("water-acceleration-battery-temperature-tamperalert.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x010F,
  zwave_product_type = 0x0B00,
  zwave_product_id = 0x1001,
})

local function test_init()
  test.mock_device.add_test_device(mock_sensor)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Basic SET 0x00 should be handled as water dry",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({value=0x00})) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.waterSensor.water.dry())
    }
  }
)

test.register_message_test(
  "Basic SET 0xFF should be handled as water wet",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({value=0xFF})) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.waterSensor.water.wet())
    }
  }
)

test.register_message_test(
  "SensorBinary Report 0xFF should be handled as acceleration active",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorBinary:Report({
        sensor_type = 0x00,
        sensor_value = 0xFF
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.accelerationSensor.acceleration.active())
    }
  }
)

test.register_message_test(
  "SensorBinary Report 0x00 should be handled as acceleration inactive",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorBinary:Report({
        sensor_type = 0x00,
        sensor_value = 0x00
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.accelerationSensor.acceleration.inactive())
    }
  }
)

test.register_message_test(
  "SensorMultilevel Report should be handled as temperature",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        sensor_value = 25
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 25, unit = 'C'}))
    }
  }
)

test.register_message_test(
  "SensorMultilevel Report 0x00 should be handled as acceleration inactive",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = 0x00,
        sensor_value = 0x00
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.accelerationSensor.acceleration.inactive())
    }
  }
)
test.register_message_test(
  "SensorMultilevel Report 0xFF should be handled as acceleration active",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = 0x00,
        sensor_value = 0xFF
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.accelerationSensor.acceleration.active())
    }
  }
)

test.register_message_test(
  "SensorAlarm report ALARM should be handled as waterSensor wet",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorAlarm:Report({
        sensor_type = SensorAlarm.sensor_type.WATER_LEAK_ALARM,
        sensor_state = SensorAlarm.sensor_state.ALARM
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
  "SensorAlarm report ALARM should be handled as waterSensor dry",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorAlarm:Report({
        sensor_type = SensorAlarm.sensor_type.WATER_LEAK_ALARM,
        sensor_state = SensorAlarm.sensor_state.NO_ALARM
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.waterSensor.water.dry())
    }
  }
)

test.register_coroutine_test(
  "SensorAlarm report ALARM should be handled as tamperAlert detected and back to clear after 30 secs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(30, "oneshot")
    test.socket.zwave:__queue_receive(
      {
        mock_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(
          SensorAlarm:Report(
            {
              sensor_type = SensorAlarm.sensor_type.GENERAL_PURPOSE_ALARM,
              sensor_state = SensorAlarm.sensor_state.ALARM
            })
        )

      }
    )
    test.socket.capability:__expect_send(mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.detected()))
    test.wait_for_events()
    test.mock_time.advance_time(30)
    test.socket.capability:__expect_send(mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
  end
)

test.register_coroutine_test(
  "SensorAlarm report ALARM should be handled as tamperAlert detected and back to clear after 30 secs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(30, "oneshot")
    test.socket.zwave:__queue_receive(
      {
        mock_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(
          SensorAlarm:Report(
            {
              sensor_type = SensorAlarm.sensor_type.SMOKE_ALARM,
              sensor_state = SensorAlarm.sensor_state.ALARM
            })
        )

      }
    )
    test.socket.capability:__expect_send(mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.detected()))
    test.wait_for_events()
    test.mock_time.advance_time(30)
    test.socket.capability:__expect_send(mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
  end
)

test.register_coroutine_test(
  "SensorAlarm report NO_ALARM should be handled as tamperAlert clear and back to clear after 30 secs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(30, "oneshot")
    test.socket.zwave:__queue_receive(
      {
        mock_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(
          SensorAlarm:Report(
            {
              sensor_type = SensorAlarm.sensor_type.GENERAL_PURPOSE_ALARM,
              sensor_state = SensorAlarm.sensor_state.NO_ALARM
            })
        )

      }
    )
    test.socket.capability:__expect_send(mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
    test.wait_for_events()
    test.mock_time.advance_time(30)
    test.socket.capability:__expect_send(mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
  end
)

test.register_coroutine_test(
  "SensorAlarm report NO_ALARM should be handled as tamperAlert detected and back to clear after 30 secs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(30, "oneshot")
    test.socket.zwave:__queue_receive(
      {
        mock_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(
          SensorAlarm:Report(
            {
              sensor_type = SensorAlarm.sensor_type.SMOKE_ALARM,
              sensor_state = SensorAlarm.sensor_state.NO_ALARM
            })
        )

      }
    )
    test.socket.capability:__expect_send(mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
    test.wait_for_events()
    test.mock_time.advance_time(30)
    test.socket.capability:__expect_send(mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
  end
)


test.run_registered_tests()
