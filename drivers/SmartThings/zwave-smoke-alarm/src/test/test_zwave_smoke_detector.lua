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
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
local SensorAlarm = (require "st.zwave.CommandClass.SensorAlarm")({ version = 1 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 2 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })

-- supported comand classes
local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.SENSOR_BINARY},
      {value = zw.SENSOR_ALARM},
      {value = zw.NOTIFICATION},
      {value = zw.ALARM},
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("smoke-battery-temperature-tamperalert-temperaturealarm.yml"),
    zwave_endpoints = sensor_endpoints
  }
)

local function  test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Sensor Binary report (smoke) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorBinary:Report({
          sensor_type = SensorBinary.sensor_type.SMOKE,
          sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      }
    }
)

test.register_message_test(
    "Sensor Alarm report (smoke detected) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorAlarm:Report({
          sensor_type = SensorAlarm.sensor_type.SMOKE_ALARM,
          sensor_state = SensorAlarm.sensor_state.ALARM
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      },
    }
)

test.register_message_test(
    "Sensor Alarm report (smoke clear ) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(SensorAlarm:Report({
          sensor_type = SensorAlarm.sensor_type.SMOKE_ALARM,
          sensor_state = SensorAlarm.sensor_state.NO_ALARM
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      },
    }
)

test.register_message_test(
    "Notification report (smoke) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.SMOKE,
          event = Notification.event.smoke.DETECTED
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      }
    }
)

test.register_message_test(
    "Notification report (smoke) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.SMOKE,
          event = Notification.event.smoke.DETECTED_LOCATION_PROVIDED
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      }
    }
)

test.register_message_test(
    "Notification report (smoke) ALARM_TEST should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.SMOKE,
          event = Notification.event.smoke.ALARM_TEST
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.tested())
      }
    }
)

test.register_message_test(
    "Notification report (smoke) STATE_IDLE should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.SMOKE,
          event = Notification.event.smoke.STATE_IDLE
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      }
    }
)

test.register_message_test(
    "Alarm report (smoke detected) should be ignored",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
          alarm_type = Alarm.z_wave_alarm_type.SMOKE,
          alarm_level = 1
        })) }
      },
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
    --   message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
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
        SensorBinary:Get({
          sensor_type = SensorBinary.sensor_type.SMOKE
        })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SensorBinary:Get({
          sensor_type = SensorBinary.sensor_type.FREEZE
        })
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
    "Notification report (HEAT) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HEAT,
          event = Notification.event.heat.OVERDETECTED_LOCATION_PROVIDED
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.heat())
      }
    }
)

test.register_message_test(
    "Notification report (HEAT) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HEAT,
          event = Notification.event.heat.RAPID_TEMPERATURE_RISE_LOCATION_PROVIDED
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.heat())
      }
    }
)

test.register_message_test(
    "Notification report (HEAT) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HEAT,
          event = Notification.event.heat.ALARM_TEST
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.heat())
      }
    }
)

test.register_message_test(
    "Notification report (HEAT) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HEAT,
          event = Notification.event.heat.STATE_IDLE
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
      }
    }
)

test.register_message_test(
    "Notification report (HEAT) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HEAT,
          event = Notification.event.heat.UNKNOWN_EVENT_STATE
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
      }
    }
)


test.register_message_test(
  "WakeUp notification should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(WakeUp:Notification({})) }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SensorBinary:Get({
          sensor_type = SensorBinary.sensor_type.FREEZE
        })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SensorBinary:Get({
          sensor_type = SensorBinary.sensor_type.SMOKE
        })
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.run_registered_tests()
