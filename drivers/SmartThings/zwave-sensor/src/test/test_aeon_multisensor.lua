-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local capabilities = require "st.capabilities"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = zw.CONFIGURATION},
      {value = zw.NOTIFICATION},
      {value = zw.SENSOR_BINARY},
      {value = zw.SENSOR_MULTILEVEL}
    }
  }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("motion-battery-temperature-illuminance-humidity.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0086,
  zwave_product_type = 0x0102,
  zwave_product_id = 0x0005,
})

local function test_init()
  test.mock_device.add_test_device(mock_sensor)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "doConfigure lifecycle event should generate the correct commands",
    function ()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_sensor.id, "doConfigure" })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({ parameter_number = 5, configuration_value = 2, size = 1 })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({ parameter_number = 3, configuration_value = 15, size = 2 })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({ parameter_number = 101, configuration_value = 225, size = 4 })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({ parameter_number = 111, configuration_value = 300, size = 4 })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorBinary:Get({sensor_type = SensorBinary.sensor_type.MOTION})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Battery:Get({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.LUMINANCE, scale = SensorMultilevel.scale.luminance.LUX})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY})
      ))
      mock_sensor:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_message_test(
  "Notification HOME_SECURITY MOTION_DETECTION should be handled as motion active",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_sensor.id,
        zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HOME_SECURITY,
          event = Notification.event.home_security.MOTION_DETECTION
        }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.active())
    }
  }
)

test.run_registered_tests()
