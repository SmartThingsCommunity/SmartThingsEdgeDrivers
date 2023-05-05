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

local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 2 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 2 })
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})

local FIBARO_MANUFACTURER_ID = 0x010F
local FIBARO_CO_SENSOR_PRODUCT_TYPE = 0x1201
local FIBARO_CO_SENSOR_PRODUCT_ID = 0x1000

local NOTIFICATIONS = 2
local TAMPERING_AND_EXCEEDING_THE_TEMPERATURE = 3
local ACOUSTIC_SIGNALS = 4
local EXCEEDING_THE_TEMPERATURE = 2
local CARBON_MONOXIDE_TEST = 0x03

-- supported comand classes
local fibaro_CO_sensor_endpoints = {
  {
    command_classes = {
      { value = zw.ALARM },
      { value = zw.BATTERY },
      { value = zw.SENSOR_MULTILEVEL },
      { value = zw.WAKE_UP }
    }
  }
}

local mock_fibaro_CO_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("fibaro-co-sensor-zw5.yml"),
  zwave_endpoints = fibaro_CO_sensor_endpoints,
  zwave_manufacturer_id = FIBARO_MANUFACTURER_ID,
  zwave_product_type = FIBARO_CO_SENSOR_PRODUCT_TYPE,
  zwave_product_id = FIBARO_CO_SENSOR_PRODUCT_ID
})

test.mock_device.add_test_device(mock_fibaro_CO_sensor)

local function test_init()
    test.mock_device.add_test_device(mock_fibaro_CO_sensor)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Device should be configured",
  function ()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_fibaro_CO_sensor.id, "doConfigure" })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_CO_sensor,
        Configuration:Set({parameter_number = NOTIFICATIONS, configuration_value = TAMPERING_AND_EXCEEDING_THE_TEMPERATURE})
    ))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_CO_sensor,
        Configuration:Set({parameter_number = ACOUSTIC_SIGNALS, configuration_value = EXCEEDING_THE_TEMPERATURE})
    ))
    mock_fibaro_CO_sensor:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_message_test(
  "Battery report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_fibaro_CO_sensor.id, zw_test_utils.zwave_test_build_receive_command(Battery:Report({ battery_level = 0x63 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_CO_sensor:generate_test_message("main", capabilities.battery.battery(99))
    }
  }
)

test.register_message_test(
  "Temperature reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_fibaro_CO_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(
          SensorMultilevel:Report({
            sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
            scale = SensorMultilevel.scale.temperature.CELSIUS,
            sensor_value = 21.5
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_CO_sensor:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 21.5, unit = 'C' }))
    }
  }
)

test.register_message_test(
  "Temperature reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_fibaro_CO_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(
          SensorMultilevel:Report({
            sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
            scale = SensorMultilevel.scale.temperature.FAHRENHEIT,
            sensor_value = 70.7
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_CO_sensor:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 70.7, unit = 'F' }))
    }
  }
)

test.register_message_test(
  "Alarm report (tamper detected) should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_fibaro_CO_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(
          Alarm:Report({
            z_wave_alarm_type = Alarm.z_wave_alarm_type.BURGLAR,
            z_wave_alarm_event = Alarm.z_wave_alarm_event.burglar.TAMPERING_PRODUCT_COVER_REMOVED
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_CO_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
    }
  }
)

test.register_message_test(
  "Alarm report (tamper clear) should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_fibaro_CO_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(
          Alarm:Report({
            z_wave_alarm_type = Alarm.z_wave_alarm_type.BURGLAR,
            z_wave_alarm_event = Notification.event.co.STATE_IDLE
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_CO_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    }
  }
)

test.register_message_test(
  "Alarm report (CO detected) should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_fibaro_CO_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(
          Alarm:Report({
            z_wave_alarm_type = Alarm.z_wave_alarm_type.CO,
            z_wave_alarm_event = Alarm.z_wave_alarm_event.co.CARBON_MONOXIDE_DETECTED
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_CO_sensor:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.detected())
    }
  }
)

test.register_message_test(
  "Alarm report (CO clear) should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_fibaro_CO_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(
          Alarm:Report({
            z_wave_alarm_type = Alarm.z_wave_alarm_type.CO,
            z_wave_alarm_event = Notification.event.co.STATE_IDLE
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_CO_sensor:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
    }
  }
)

test.register_message_test(
  "Alarm report (CO test) should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_fibaro_CO_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
        z_wave_alarm_type = Alarm.z_wave_alarm_type.CO,
        z_wave_alarm_event = CARBON_MONOXIDE_TEST,
        event_parameter = ""

      }))}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_CO_sensor:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.tested())
    }
  }
)

test.register_message_test(
  "Alarm report (CO test clear) should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_fibaro_CO_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(
          Alarm:Report({
            z_wave_alarm_type = Alarm.z_wave_alarm_type.CO,
            z_wave_alarm_event = CARBON_MONOXIDE_TEST,
            event_parameter = ""
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_CO_sensor:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
    }
  }
)

test.register_message_test(
  "Temperature alarm report (heat) should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_fibaro_CO_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(
          Alarm:Report({
            z_wave_alarm_type = Alarm.z_wave_alarm_type.HEAT,
            z_wave_alarm_event = Alarm.z_wave_alarm_event.heat.OVERDETECTED
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_CO_sensor:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.heat())
    }
  }
)

test.register_message_test(
  "Temperature alarm report (heat clear) should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_fibaro_CO_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(
          Alarm:Report({
            z_wave_alarm_type = Alarm.z_wave_alarm_type.HEAT,
            z_wave_alarm_event = Notification.event.heat.STATE_IDLE
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_CO_sensor:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    }
  }
)


test.register_message_test(
  "Sending initial states when device is added",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {mock_fibaro_CO_sensor.id, "added"}
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_fibaro_CO_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    -- },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_fibaro_CO_sensor:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
    -- },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_fibaro_CO_sensor:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    -- }
  },
  {
    inner_block_ordering = "relaxed"
  }
)


test.register_coroutine_test(
  "Device should be configured after changing device settings",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    local _preferences = {zwaveNotifications = 3} --"Both actions enabled"
    test.socket.device_lifecycle():__queue_receive(mock_fibaro_CO_sensor:generate_info_changed({ preferences = _preferences }))

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_CO_sensor,
        Configuration:Set({
          parameter_number = 2,
          configuration_value = 3,
          size = 1
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_CO_sensor,
        Configuration:Get({ parameter_number = 2 })
      )
    )

    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_fibaro_CO_sensor.id,
      Configuration:Report({ parameter_number = 2, configuration_value = 3 })
    })

    test.mock_time.advance_time(1)

    _preferences = {overheatThreshold = 50} --"120 °F / 50°C"
    test.socket.device_lifecycle():__queue_receive(mock_fibaro_CO_sensor:generate_info_changed({ preferences = _preferences }))

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_CO_sensor,
        Configuration:Set({
          parameter_number = 22,
          configuration_value = 50,
          size = 1
        })
      )
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_CO_sensor,
        Configuration:Get({ parameter_number = 22 })
      )
    )

    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_fibaro_CO_sensor.id,
      Configuration:Report({ parameter_number = 22, configuration_value = 50 })
    })
  end
)

test.run_registered_tests()
