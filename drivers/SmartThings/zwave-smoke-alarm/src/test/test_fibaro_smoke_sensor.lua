-- Copyright 2021 SmartThings
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

local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })

-- supported comand classes
local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.SENSOR_BINARY},
      {value = zw.SENSOR_ALARM},
      {value = zw.NOTIFICATION},
      {value = zw.ALARM}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("smoke-battery-temperature-tamperalert-temperaturealarm.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x010F,
    zwave_product_type = 0x0C02,
    zwave_product_id = 0x1002    
  }
)

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
                smokeSensorSensitivity = 0,
                zwaveNotificationStatus = 2,
                indicatorNotification = 4,
                soundNotificationStatus = 7,
                tempReportInterval = 30,
                tempReportHysteresis= 50,
                temperatureThreshold= 75,
                overheatInterval= 90,
                outOfRange= 4320
              }
          }
      ))

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=1, size=1, configuration_value=0})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=2, size=1, configuration_value=2})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=3, size=1, configuration_value=4})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=4, size=1, configuration_value=7})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=20, size=2, configuration_value=30})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=21, size=2, configuration_value=50})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=30, size=2, configuration_value=75})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=31, size=2, configuration_value=90})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=32, size=2, configuration_value=4320})
          )
      )

    end
)

test.register_coroutine_test(
    "added lifecycle event should get initial state for device",
    function()
        test.socket.zwave:__set_channel_ordering("relaxed")
        test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added"})
        test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_device,
            WakeUp:IntervalSet({node_id = 0x00, seconds = 21600})
        ))
    end
)

test.register_coroutine_test(
    "WakeUp notificaiton command should be handled",
    function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.zwave:__queue_receive({mock_device.id, WakeUp:Notification({}) })
    test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
    )
    end
)



test.run_registered_tests()
