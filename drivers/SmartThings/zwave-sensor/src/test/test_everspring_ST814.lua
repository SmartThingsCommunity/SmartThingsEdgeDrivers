-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.CONFIGURATION}
    }
  }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("humidity-temperature-battery.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0060,
  zwave_product_type = 0x0006,
  zwave_product_id = 0x0001,
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
          Configuration:Set({parameter_number = 6, size = 2, configuration_value = 20})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 7, size = 1, configuration_value = 2})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 8, size = 1, configuration_value = 5})
      ))
      mock_sensor:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.run_registered_tests()
