-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = zw.CONFIGURATION},
      {value = zw.NOTIFICATION},
      {value = zw.SENSOR_MULTILEVEL},
      {value = zw.WAKE_UP}
    }
  }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("water-illuminance-temperature.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x019A,
  zwave_product_type = 0x0003,
  zwave_product_id = 0x000A,
})

local function test_init()
  test.mock_device.add_test_device(mock_sensor)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "lifecycle configure event should configure device",
    function ()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_sensor.id, "doConfigure" })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.LUMINANCE, scale = SensorMultilevel.scale.luminance.LUX})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Battery:Get({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Get({ parameter_number = 12 })
      ))
      mock_sensor:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
  "Configuration report should update metadata",
  function()
    test.socket.zwave:__queue_receive({mock_sensor.id, Configuration:Report( { configuration_value = 0x00, parameter_number = 12 } )})
    mock_sensor:expect_metadata_update({ profile = "illuminance-temperature" })
  end
)

test.register_coroutine_test(
  "Wakeup Notification should prompt a configuration get until a report is received",
  function ()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.zwave:__queue_receive({mock_sensor.id, WakeUp:Notification({})})
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_sensor,
      Configuration:Get({ parameter_number = 12})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_sensor,
      WakeUp:IntervalGet({})
    ))
    test.socket.zwave:__queue_receive({mock_sensor.id, Configuration:Report( { configuration_value = 0x00, parameter_number = 12 } )})
    mock_sensor:expect_metadata_update({ profile = "illuminance-temperature" })
    test.socket.zwave:__queue_receive({mock_sensor.id, WakeUp:Notification({})})
  end
)

test.run_registered_tests()
