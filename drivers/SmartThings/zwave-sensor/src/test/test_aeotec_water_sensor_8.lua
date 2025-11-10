-- Copyright 2025 SmartThings
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
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = zw.NOTIFICATION},
      {value = zw.SENSOR_MULTILEVEL},
      {value = zw.CONFIGURATION}
    }
  }
}

local mock_water_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-water-sensor-8.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0002,
  zwave_product_id = 0x0038,
})

local mock_co_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-water-sensor-8-co.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0002,
  zwave_product_id = 0x0038,
})

local mock_co2_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-water-sensor-8-co2.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0002,
  zwave_product_id = 0x0038,
})

local mock_contact_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-water-sensor-8-contact.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0002,
  zwave_product_id = 0x0038,
})

local mock_glass_break_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-water-sensor-8-glass-break.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0002,
  zwave_product_id = 0x0038,
})

local mock_motion_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-water-sensor-8-motion.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0002,
  zwave_product_id = 0x0038,
})

local mock_panic_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-water-sensor-8-panic.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0002,
  zwave_product_id = 0x0038,
})

local mock_smoke_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-water-sensor-8-smoke.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0002,
  zwave_product_id = 0x0038,
})

DEVICE_PROFILES = {
  [0] = {
    profile = "aeotec-water-sensor-8",
    mock_device = mock_water_sensor,
    default_cap = capabilities.waterSensor.water.dry(),
    active_cap = capabilities.waterSensor.water.wet(),
    default_cap_str = "dry",
    active_cap_str = "wet",
    notification_typ = Notification.notification_type.WATER,
    on_event = Notification.event.water.LEAK_DETECTED,
    off_event = Notification.event.water.STATE_IDLE
  },
  [1] = {
    profile = "aeotec-water-sensor-8-smoke",
    mock_device = mock_smoke_sensor,
    default_cap = capabilities.smokeDetector.smoke.clear(),
    active_cap = capabilities.smokeDetector.smoke.detected(),
    default_cap_str = "clear",
    active_cap_str = "detected",
    notification_typ = Notification.notification_type.SMOKE,
    on_event = Notification.event.smoke.DETECTED,
    off_event =  Notification.event.smoke.STATE_IDLE
  },
  [2] = {
    profile = "aeotec-water-sensor-8-co",
    mock_device = mock_co_sensor,
    default_cap = capabilities.carbonMonoxideDetector.carbonMonoxide.clear(),
    active_cap = capabilities.carbonMonoxideDetector.carbonMonoxide.detected(),
    default_cap_str = "clear",
    active_cap_str = "detected",
    notification_typ = Notification.notification_type.CO,
    on_event = Notification.event.co.CARBON_MONOXIDE_DETECTED,
    off_event = Notification.event.co.STATE_IDLE
  },
  [3] = {
    profile = "aeotec-water-sensor-8-co2",
    mock_device = mock_co2_sensor,
    default_cap = capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern.good(),
    active_cap = capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern.moderate(),
    default_cap_str = "good",
    active_cap_str = "moderate",
    notification_typ = Notification.notification_type.CO2,
    on_event = Notification.event.co2.CARBON_DIOXIDE_DETECTED,
    off_event = Notification.event.co2.STATE_IDLE
  },
  [4] = {
    profile = "aeotec-water-sensor-8-contact",
    mock_device = mock_contact_sensor,
    default_cap = capabilities.contactSensor.contact.closed(),
    active_cap = capabilities.contactSensor.contact.open(),
    default_cap_str = "closed",
    active_cap_str = "open",
    notification_typ = Notification.notification_type.ACCESS_CONTROL,
    on_event = Notification.event.access_control.WINDOW_DOOR_IS_OPEN,
    off_event = Notification.event.access_control.WINDOW_DOOR_IS_CLOSED
  },
  [5] = {
    profile = "aeotec-water-sensor-8-contact",
    mock_device = mock_contact_sensor,
    default_cap = capabilities.contactSensor.contact.closed(),
    active_cap = capabilities.contactSensor.contact.open(),
    default_cap_str = "closed",
    active_cap_str = "open",
    notification_typ = Notification.notification_type.ACCESS_CONTROL,
    on_event = Notification.event.access_control.WINDOW_DOOR_IS_OPEN,
    off_event = Notification.event.access_control.WINDOW_DOOR_IS_CLOSED
  },
  [6] = {
    profile = "aeotec-water-sensor-8-motion",
    mock_device = mock_motion_sensor,
    default_cap = capabilities.motionSensor.motion.inactive(),
    active_cap = capabilities.motionSensor.motion.active(),
    default_cap_str = "inactive",
    active_cap_str = "active",
    notification_typ = Notification.notification_type.HOME_SECURITY,
    on_event = Notification.event.home_security.MOTION_DETECTION,
    off_event = Notification.event.home_security.STATE_IDLE
  },
  [7] = {
    profile = "aeotec-water-sensor-8-glass-break",
    mock_device = mock_glass_break_sensor,
    default_cap = capabilities.soundDetection.soundDetected.noSound(),
    active_cap = capabilities.soundDetection.soundDetected.glassBreaking(),
    default_cap_str = "noSound",
    active_cap_str = "glassBreaking",
    notification_typ = Notification.notification_type.HOME_SECURITY,
    on_event = Notification.event.home_security.GLASS_BREAKAGE,
    off_event = Notification.event.home_security.STATE_IDLE
  },
  [8] = {
    profile = "aeotec-water-sensor-8-panic",
    mock_device = mock_panic_sensor,
    default_cap = capabilities.panicAlarm.panicAlarm.clear(),
    active_cap =  capabilities.panicAlarm.panicAlarm.panic(),
    default_cap_str = "clear",
    active_cap_str = "panic",
    notification_typ = Notification.notification_type.EMERGENCY,
    on_event = Notification.event.emergency.PANIC_ALERT,
    off_event = Notification.event.emergency.STATE_IDLE
  }
}

local function test_init()
  test.mock_device.add_test_device(mock_water_sensor)
  test.mock_device.add_test_device(mock_smoke_sensor)
  test.mock_device.add_test_device(mock_co_sensor)
  test.mock_device.add_test_device(mock_co2_sensor)
  test.mock_device.add_test_device(mock_contact_sensor)
  test.mock_device.add_test_device(mock_contact_sensor)
  test.mock_device.add_test_device(mock_motion_sensor)
  test.mock_device.add_test_device(mock_glass_break_sensor)
  test.mock_device.add_test_device(mock_panic_sensor)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Device added lifecycle event for profile",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_water_sensor.id, "added" })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_water_sensor,
        Configuration:Get({
          parameter_number = 10
        })
      )
    )
    test.socket.capability:__expect_send(
      mock_water_sensor:generate_test_message("main", capabilities.moldHealthConcern.supportedMoldValues({"good", "moderate"}))
    )

    test.socket.capability:__expect_send(
      mock_water_sensor:generate_test_message("main", capabilities.moldHealthConcern.moldHealthConcern.good())
    )

    test.socket.capability:__expect_send(
      mock_water_sensor:generate_test_message("main", capabilities.powerSource.powerSource.battery())
    )


    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_water_sensor,
        Battery:Get({})
      )
    )
  end
)

test.register_message_test(
  "Refresh should generate the correct commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_water_sensor.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_water_sensor,
        Battery:Get({})
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
    "Notification report STATE_IDLE event should be handled tamper alert state clear",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_water_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HOME_SECURITY,
          event = Notification.event.home_security.STATE_IDLE,
          event_parameter = string.char(Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED)
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_water_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      }
    }
)

test.register_coroutine_test(
    "Notification report TAMPERING_PRODUCT_COVER_REMOVED event should be handled as tamperAlert detected",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(10, "oneshot")
      test.socket.zwave:__queue_receive(
        {
          mock_water_sensor.id,
          zw_test_utils.zwave_test_build_receive_command(
            Notification:Report(
              {
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED
              })
          )
        }
      )
      test.socket.capability:__expect_send(mock_water_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.detected()))
    end
)

test.register_message_test(
    "Battery report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_water_sensor.id, zw_test_utils.zwave_test_build_receive_command(Battery:Report({ battery_level = 0x63 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_water_sensor:generate_test_message("main", capabilities.battery.battery(99))
      }
    }
)

test.register_message_test(
  "Notification report AC_MAINS_DISCONNECTED event should be handled power source state battery",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_water_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.POWER_MANAGEMENT,
        event = Notification.event.power_management.AC_MAINS_DISCONNECTED,
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_water_sensor:generate_test_message("main", capabilities.powerSource.powerSource.battery())
    }
  }
)

test.register_message_test(
  "Notification report AC_MAINS_RE_CONNECTED event should be handled power source state dc",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_water_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.POWER_MANAGEMENT,
        event = Notification.event.power_management.AC_MAINS_RE_CONNECTED,
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_water_sensor:generate_test_message("main", capabilities.powerSource.powerSource.dc())
    }
  }
)

test.register_message_test(
  "Notification report POWER_HAS_BEEN_APPLIED event should be send battery get",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_water_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.POWER_MANAGEMENT,
        event = Notification.event.power_management.POWER_HAS_BEEN_APPLIED,
      })) }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_water_sensor,
        Battery:Get({})
      )
    }
  }
)

test.register_message_test(
    "Notification report LEAK_DETECTED event should be handled water sensor state wet",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_water_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.WATER,
          event = Notification.event.water.LEAK_DETECTED,
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_water_sensor:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "Notification report STATE_IDLE event should be handled water sensor state dry",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_water_sensor.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.WATER,
          event = Notification.event.water.STATE_IDLE,
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_water_sensor:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)


for param_value, data in pairs(DEVICE_PROFILES) do
  local value = param_value
  local profile = data.profile
  local mock_device = data.mock_device
  local default_cap = data.default_cap
  local active_cap = data.active_cap
  local notification_type = data.notification_typ
  local on_event = data.on_event
  local off_event = data.off_event


  test.register_coroutine_test(
    "Profile should update when Configuration Report parameter 10 = "  .. value,
    function()
      test.socket.zwave:__queue_receive({
        mock_device.id,
        Configuration:Report({
          parameter_number = 10,
          configuration_value = value
        })
      })

      test.socket.device_lifecycle:__expect_send(
        mock_device:expect_metadata_update({
          profile = profile
        })
      )

      if profile == "aeotec-water-sensor-8-glass-break" then
        test.socket.capability:__expect_send(
          mock_device:generate_test_message("main", capabilities.soundDetection.supportedSoundTypes({"noSound", "glassBreaking"}))
        )
      elseif profile == "aeotec-water-sensor-8-co2" then
        test.socket.capability:__expect_send(
          mock_device:generate_test_message("main", capabilities.carbonDioxideHealthConcern.supportedCarbonDioxideValues({"good", "moderate"}))
        )
      end

      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", default_cap)
      )
    end
  )

  test.register_coroutine_test(
    "Notification report type " .. notification_type .. " event ".. off_event .. " should be handled "  .. data.default_cap_str,
    function()
      mock_device:set_field("active_profile", profile)

      test.socket.zwave:__queue_receive({
        mock_device.id,
        Notification:Report({
          notification_type = notification_type,
          event = off_event,
          event_parameter = string.char(on_event)
        })
      })

      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", default_cap)
      )
    end
  )

  test.register_coroutine_test(
    "Notification report type " .. notification_type .. " event ".. on_event .. " should be handled "  .. data.active_cap_str,
    function()
      mock_device:set_field("active_profile", profile)

      test.socket.zwave:__queue_receive({
        mock_device.id,
        Notification:Report({
          notification_type = notification_type,
          event = on_event,
        })
      })

      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", active_cap)
      )
    end
  )
end

test.run_registered_tests()