-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 2 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.ALARM},
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("base-sound.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x014A,
    zwave_product_type = 0x0005,
    zwave_product_id = 0x000F
  }
)

local function  test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Alarm report should be handled as sound detected",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
        z_wave_alarm_type = Alarm.z_wave_alarm_type.SMOKE,
        z_wave_alarm_event = Alarm.z_wave_alarm_event.smoke.DETECTED_LOCATION_PROVIDED
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.soundSensor.sound.detected())
    }
  }
)

test.register_message_test(
  "Alarm report should be handled as sound not detected",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
        z_wave_alarm_type = Alarm.z_wave_alarm_type.BURGLAR,
        z_wave_alarm_event = Alarm.z_wave_alarm_event.burglar.TAMPERING_PRODUCT_COVER_REMOVED
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.soundSensor.sound.not_detected())
    }
  }
)

test.register_message_test(
  "added lifecycle event should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "added" }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.soundSensor.sound.not_detected())
    }
  }
)

test.run_registered_tests()
