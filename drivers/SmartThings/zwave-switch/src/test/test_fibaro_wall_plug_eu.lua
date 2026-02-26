-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})
local t_utils = require "integration_test.utils"

-- supported comand classes
local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.METER},
      {value = zw.SWITCH_BINARY},
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("fibaro-metering-switch.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x010F,
    zwave_product_type = 0x0602,
    zwave_product_id = 0x1001
})

local function  test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
    "infoChanged() should send the SET command for Configuation value",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive({mock_device.id, "init"})
      test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed(
          {
              preferences = {
                alwaysActive = 1,
                restoreState = 0,
                overloadSafety = 500,
                standardPowerReports = 50,
                powerReportFrequency = 250,
                periodicReports = 5000,
                ringColorOn = 4,
                ringColorOff = 5
              }
          }
      ))

      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
            mock_device,
            Configuration:Set({parameter_number=1, size=1, configuration_value=1})
        )
    )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=2, size=1, configuration_value=0})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=3, size=2, configuration_value=500})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=11, size=1, configuration_value=50})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=12, size=2, configuration_value=250})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=14, size=2, configuration_value=5000})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=41, size=1, configuration_value=4})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=42, size=1, configuration_value=5})
          )
      )

    end,
    {
       min_api_version = 19
    }
)

test.run_registered_tests()
