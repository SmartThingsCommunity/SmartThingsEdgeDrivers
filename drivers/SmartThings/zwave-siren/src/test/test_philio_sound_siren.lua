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

local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Basic = (require "st.zwave.CommandClass.Basic")({version =1})
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({version=2})
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})

local SMOKE = 0
local EMERGENCY = 1
local POLICE = 2
local FIRE = 3
local AMBULANCE = 4

local siren_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.NOTIFICATION},
      {value = zw.SENSOR_BINARY}
    }
  }
}

local mock_siren = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("philio-sound-siren.yml"),
  zwave_endpoints = siren_endpoints,
  zwave_manufacturer_id = 0x013C,
  zwave_product_type = 0x0004,
  zwave_product_id = 0x000A
})

local function test_init()
  test.mock_device.add_test_device(mock_siren)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "SensorBinary report 0xFF, sensor type TAMPER should be handled as alarm both, tamper detected, chime",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_siren.id,
        zw_test_utils.zwave_test_build_receive_command(SensorBinary:Report({
          sensor_type = SensorBinary.sensor_type.TAMPER,
          sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "SensorBinary report 0xFF, sensor type GENERAL should be handled as alarm both, tamper detected, chime",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_siren.id,
        zw_test_utils.zwave_test_build_receive_command(SensorBinary:Report({
          sensor_type = SensorBinary.sensor_type.GENERAL,
          sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.alarm.alarm.both())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.switch.switch.on())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "SensorBinary report 0x00 should be handled as alarm off, tamper clear, chime off",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_siren.id,
        zw_test_utils.zwave_test_build_receive_command(SensorBinary:Report({
          sensor_type = SensorBinary.sensor_type.GENERAL,
          sensor_value = SensorBinary.sensor_value.IDLE
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.alarm.alarm.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.chime.chime.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.switch.switch.off())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Basic report 0xFF should be handled as alarm both, chime",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_siren.id,
        zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0xFF})) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.alarm.alarm.both())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.chime.chime.chime())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.switch.switch.on())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)


test.register_message_test(
  "Basic report 0x00 should be handled as alarm off, chime off",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_siren.id,
        zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0x00})) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.alarm.alarm.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.chime.chime.off())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.switch.switch.off())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Notification report home security type TAMPERING_PRODUCT_COVER_REMOVED should be handled as tamper alert detected",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.HOME_SECURITY,
        event = Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Notification report home security type STATE_IDLE should be handled as tamper clear, chime off",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.HOME_SECURITY,
        event = Notification.event.home_security.STATE_IDLE
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_siren:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
  "Chime capability / chime command should evoke the correct Z-Wave Notification commands",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_siren.id,
      { capability = "chime", component = "main", command = "chime", args = {} }
    })

    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("main", capabilities.chime.chime.chime())
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Notification:Report({
          notification_type = Notification.notification_type.ACCESS_CONTROL,
          event =             Notification.event.access_control.WINDOW_DOOR_IS_OPEN
        })
      )
    )

    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.capability:__expect_send(
      mock_siren:generate_test_message("main", capabilities.chime.chime.off())
    )
  end
)

test.register_coroutine_test(
  "Alarm capability / siren command should evoke the correct Z-Wave commands / SMOKE sound selected",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed({preferences = {sound = SMOKE}}))
    test.wait_for_events()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_siren.id,
        {component = "main", capability = "alarm", command = "siren", args = {} }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
      mock_siren,
      Notification:Report({
        notification_type = Notification.notification_type.SMOKE,
        event             = Notification.event.smoke.DETECTED_LOCATION_PROVIDED
      })
      )
    )
  end
)

test.register_coroutine_test(
  "Alarm capability / siren command should evoke the correct Z-Wave commands / Default sound (EMERGENCY) should be used",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_siren.id,
        {component = "main", capability = "alarm", command = "siren", args = {} }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Notification:Report({
          notification_type = Notification.notification_type.HOME_SECURITY,
          event             = Notification.event.home_security.INTRUSION_LOCATION_PROVIDED
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Alarm capability / siren command should evoke the correct Z-Wave commands / EMERGENCY sound selected",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed({preferences = {sound = EMERGENCY}}))
    test.wait_for_events()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_siren.id,
        {component = "main", capability = "alarm", command = "siren", args = {} }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Notification:Report({
          notification_type = Notification.notification_type.HOME_SECURITY,
          event             = Notification.event.home_security.INTRUSION_LOCATION_PROVIDED
        })
      )
    )
  end
)

test.register_coroutine_test(
    "Alarm capability / siren command should evoke the correct Z-Wave commands / POLICE sound selected",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed({preferences = {sound = POLICE}}))
      test.wait_for_events()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
        {
          mock_siren.id,
          {component = "main", capability = "alarm", command = "siren", args = {} }
        }
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Notification:Report({
            notification_type = Notification.notification_type.EMERGENCY,
            event             = Notification.event.emergency.CONTACT_POLICE
          })
        )
      )
    end
)

test.register_coroutine_test(
  "Alarm capability / siren command should evoke the correct Z-Wave commands / FIRE sound selected",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed({preferences = {sound = FIRE}}))
    test.wait_for_events()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_siren.id,
        {component = "main", capability = "alarm", command = "siren", args = {} }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Notification:Report({
          notification_type = Notification.notification_type.EMERGENCY,
          event             = Notification.event.emergency.CONTACT_FIRE_SERVICE
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Alarm capability / siren command should evoke the correct Z-Wave commands / AMBULANCE sound selected",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed({preferences = {sound = AMBULANCE}}))
    test.wait_for_events()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_siren.id,
        {component = "main", capability = "alarm", command = "siren", args = {} }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Notification:Report({
          notification_type = Notification.notification_type.EMERGENCY,
          event             = Notification.event.emergency.CONTACT_MEDICAL_SERVICE
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Alarm capability / off command should evoke the correct Z-Wave commands",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_siren.id,
        { capability = "alarm", command = "off", args = {} }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value=0x00})
      )
    )
  end
)

do
  local new_duration = 90
  test.register_coroutine_test(
    "Parameter duration should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed({preferences = {duration = new_duration}}))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
                mock_siren,
          Configuration:Set({
            parameter_number = 31,
            configuration_value = new_duration,
            size = 1
          })
        )
      )
    end
  )
end

do
  test.register_coroutine_test(
    "Parameter sound should be updated in the device configuration after change (verified by triggering siren capability events)",
    function()

      test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed({preferences = {sound = POLICE}}))

      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_siren.id,
          {component = "main", capability = "alarm", command = "siren", args = {} }
        }
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
            mock_siren,
            Notification:Report({
              notification_type = Notification.notification_type.EMERGENCY,
              event             = Notification.event.emergency.CONTACT_POLICE
            })
        )
      )
      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive(mock_siren:generate_info_changed({preferences = {sound = AMBULANCE}}))
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_siren.id,
          {component = "main", capability = "alarm", command = "siren", args = {} }
        }
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Notification:Report({
            notification_type = Notification.notification_type.EMERGENCY,
            event             = Notification.event.emergency.CONTACT_MEDICAL_SERVICE
          })
        )
      )
    end
  )
end

test.register_message_test(
  "Device should be polled with refresh right after inclusion",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_siren.id, "added" }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              Basic:Get({})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.run_registered_tests()
