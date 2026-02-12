-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })
local t_utils = require "integration_test.utils"
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({version = 5})

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.BATTERY},
      {value = zw.WAKE_UP}
    }
  }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("motion-battery-illuminance-temperature-interval.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x001E,
  zwave_product_type = 0x0002,
  zwave_product_id = 0x0001,
})

local function test_init()
  test.mock_device.add_test_device(mock_sensor)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Basic set value 0xFF should be handled as proper capabilities",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({ value = 0xFF })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "Basic set value 0x00 should be handled as proper capabilities",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({ value = 0x00 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    }
)

test.register_message_test(
  "Device Added handler should be generate wakeup interval set command",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_sensor.id, "added" }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        WakeUp:IntervalSet({node_id = 0x00, seconds = 1200})
      )
    }
  }
)

test.register_coroutine_test(
    "Reporting interval value should be updated when wakeup notification received",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive({mock_sensor.id, "init"})
      test.socket.device_lifecycle():__queue_receive(mock_sensor:generate_info_changed(
          {
              preferences = {
                reportingInterval = 10
              }
          }
      ))
      test.wait_for_events()
      test.socket.zwave:__queue_receive(
        {
          mock_sensor.id,
          WakeUp:Notification({})
        }
      )
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        WakeUp:IntervalSet({node_id = 0x00, seconds = 10 * 60})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        WakeUp:IntervalGet({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        Battery:Get({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE}, {dst_channels={3}})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.LUMINANCE}, {dst_channels={2}})
      ))
    end
)
test.register_coroutine_test(
    "Receiving wakeup notification should generate proper messages",
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
        WakeUp:IntervalGet({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE}, {dst_channels={3}})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.LUMINANCE}, {dst_channels={2}})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        Battery:Get({})
      ))
    end
)
test.run_registered_tests()
