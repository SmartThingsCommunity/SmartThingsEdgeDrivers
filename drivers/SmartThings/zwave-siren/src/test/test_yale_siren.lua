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

local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=1})
local Battery = (require "st.zwave.CommandClass.Battery")({version=1})
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})
local t_utils = require "integration_test.utils"

-- supported comand classes
local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.CONFIGURATION},
      {value = zw.SWITCH_BINARY}
    }
  }
}

local mock_siren = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("yale-siren.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x0129,
    zwave_product_type = 0x6F01,
    zwave_product_id = 0x0001
})

local function test_init()
  test.mock_device.add_test_device(mock_siren)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Basic report 0x00 should be handled as alarm off",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_siren.id,
          zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0x00 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren:generate_test_message("main", capabilities.alarm.alarm.off())
      }
    }
)

test.register_message_test(
    "Basic report 0xFF should be handled as alarm both",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_siren.id,
          zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0xFF })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren:generate_test_message("main", capabilities.alarm.alarm.both())
      }
    }
)

test.register_coroutine_test(
    "Setting alarm both should generate correct zwave messages",
    function()
      test.socket.zwave:__set_channel_ordering('relaxed')
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_siren.id,
            { capability = "alarm", command = "both", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              Basic:Set({value=0xFF})
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(3)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              Basic:Get({})
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              SwitchBinary:Get({})
          )
      )
    end
)


test.register_coroutine_test(
    "Setting alarm siren should generate correct zwave messages",
    function()
      test.socket.zwave:__set_channel_ordering('relaxed')
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_siren.id,
            { capability = "alarm", command = "siren", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              Basic:Set({value=0xFF})
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(3)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              Basic:Get({})
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              SwitchBinary:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting alarm strobe should generate correct zwave messages",
    function()
      test.socket.zwave:__set_channel_ordering('relaxed')
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_siren.id,
            { capability = "alarm", command = "strobe", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              Basic:Set({value=0xFF})
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(3)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              Basic:Get({})
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              SwitchBinary:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting alarm off should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
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
      test.wait_for_events()

      test.mock_time.advance_time(3)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              Basic:Get({})
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              SwitchBinary:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Yale Siren should be correctly configured",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zwave:__set_channel_ordering('relaxed')
      test.socket.device_lifecycle:__queue_receive({ mock_siren.id, "doConfigure" })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Set({parameter_number = 1, size = 1, configuration_value = 10})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Set({parameter_number = 2, size = 1, configuration_value = 1})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Set({parameter_number = 3, size = 1, configuration_value = 0})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Set({parameter_number = 4, size = 1, configuration_value = 0})
      ))
      mock_siren:expect_metadata_update({ provisioning_state = "PROVISIONED" })
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Basic:Set({value=0x00})
      ))
    end
)

test.register_coroutine_test(
    "Yale Siren's configuration should be updated when triggered by user",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zwave:__set_channel_ordering('relaxed')
      test.socket.device_lifecycle():__queue_receive(mock_siren:generate_info_changed(
          {
              preferences = {
                ["certifiedpreferences.alarmLength"] = 5,
                ["certifiedpreferences.alarmLEDflash"] = 0,
                ["certifiedpreferences.comfortLED"] = 10,
                ["certifiedpreferences.tamper"] = 0
              }
          }
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Set({parameter_number = 1, size = 1, configuration_value = 5})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Set({parameter_number = 2, size = 1, configuration_value = 0})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Set({parameter_number = 3, size = 1, configuration_value = 10})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Set({parameter_number = 4, size = 1, configuration_value = 0})
      ))

      test.mock_time.advance_time(1)

      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Basic:Set({value=0x00})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Get({parameter_number = 4})
      ))
    end
)

test.register_coroutine_test(
  "Yale Siren should refresh attributes when added",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zwave:__set_channel_ordering('relaxed')
    test.socket.device_lifecycle:__queue_receive({ mock_siren.id, "added" })
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_siren,
      SwitchBinary:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_siren,
      Battery:Get({})
    ))
  end
)

test.run_registered_tests()
