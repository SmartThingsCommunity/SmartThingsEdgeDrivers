-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.CONFIGURATION},
      {value = zw.SWITCH_BINARY},
      {value = zw.SWITCH_MULTILEVEL},
    }
  }
}

local mock_dimmer = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("switch-level.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0039,
  zwave_product_type = 0x4944,
  zwave_product_id = 0x3130,
})

local function test_init()
  test.mock_device.add_test_device(mock_dimmer)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "lifecycle configure event should configure device",
    function ()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_dimmer.id, "doConfigure" })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_dimmer,
          Configuration:Set({parameter_number=7, configuration_value=1, size=1})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_dimmer,
          Configuration:Set({parameter_number=8, configuration_value=1, size=2})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_dimmer,
          Configuration:Set({parameter_number=9, configuration_value=1, size=1})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_dimmer,
          Configuration:Set({parameter_number=10, configuration_value=1, size=2})
      ))
      mock_dimmer:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end,
    {
       min_api_version = 19
    }
)

test.run_registered_tests()
