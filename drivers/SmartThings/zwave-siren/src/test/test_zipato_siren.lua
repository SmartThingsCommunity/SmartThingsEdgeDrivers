-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local Battery = (require "st.zwave.CommandClass.Battery")({version=1})
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})

-- supported comand classes
local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.CONFIGURATION}
    }
  }
}

local mock_siren = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("alarm-battery.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x0131,
    zwave_product_type = 0x0003,
    zwave_product_id = 0x1083
})

local function test_init()
  test.mock_device.add_test_device(mock_siren)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Zipato Siren should be correctly configured",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zwave:__set_channel_ordering('relaxed')
      test.socket.device_lifecycle:__queue_receive({ mock_siren.id, "doConfigure" })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Set({parameter_number = 1, size = 1, configuration_value = 3})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Set({parameter_number = 2, size = 1, configuration_value = 2})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Set({parameter_number = 5, size = 1, configuration_value = 10})
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
      test.mock_time.advance_time(63)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              Basic:Get({})
          )
      )
    end
)

test.register_coroutine_test(
  "Siren should refresh attributes when added",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zwave:__set_channel_ordering('relaxed')
    test.socket.device_lifecycle:__queue_receive({ mock_siren.id, "added" })
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_siren,
      Basic:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_siren,
      Battery:Get({})
    ))
  end
)

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

test.run_registered_tests()
