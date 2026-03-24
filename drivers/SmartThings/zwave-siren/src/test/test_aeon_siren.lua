-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})
local t_utils = require "integration_test.utils"

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
    profile = t_utils.get_profile_definition("aeon-siren.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x0086,
    zwave_product_type = 0x0004,
    zwave_product_id = 0x0050
})

local function test_init()
  test.mock_device.add_test_device(mock_siren)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Basic report 0x00 should be handled as alarm off, swtich off",
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
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren:generate_test_message("main", capabilities.switch.switch.off())
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "Basic report 0xFF should be handled as alarm both, swtich on",
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
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren:generate_test_message("main", capabilities.switch.switch.on())
      }
    },
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "Setting switch on should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_siren.id,
            { capability = "switch", command = "on", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              Basic:Set({value=0xFF})
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              Basic:Get({})
          )
      )
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "Setting alarm both should generate correct zwave messages",
    function()
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

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              Basic:Get({})
          )
      )
    end,
    {
       min_api_version = 19
    }
)


test.register_coroutine_test(
    "Setting alarm siren should generate correct zwave messages",
    function()
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

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              Basic:Get({})
          )
      )
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "Setting alarm strobe should generate correct zwave messages",
    function()
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

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              Basic:Get({})
          )
      )
    end,
    {
       min_api_version = 19
    }
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

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_siren,
              Basic:Get({})
          )
      )
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "Aeon Siren should be correctly configured",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.device_lifecycle:__queue_receive({ mock_siren.id, "doConfigure" })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Set({parameter_number = 80, size = 1, configuration_value = 2})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Set({parameter_number = 37, size = 2, configuration_value = 259})
      ))
      mock_siren:expect_metadata_update({ provisioning_state = "PROVISIONED" })
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Basic:Set({value=0x00})
      ))
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "Siren's sound configuration should be updated when triggered by user with just one option changed",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.device_lifecycle():__queue_receive(mock_siren:generate_info_changed(
          {
              preferences = {
                volume = 2
              }
          }
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Set({parameter_number = 37, size = 2, configuration_value = 1 << 8 | 2})
      ))
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Basic:Set({value=0x00})
      ))
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "Siren's sound configuration should be updated when triggered by user with both options changed",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.device_lifecycle():__queue_receive(mock_siren:generate_info_changed(
          {
              preferences = {
                type = 3,
                volume = 2
              }
          }
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Configuration:Set({parameter_number = 37, size = 2, configuration_value = 3 << 8 | 2})
      ))
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_siren,
          Basic:Set({value=0x00})
      ))
    end,
    {
       min_api_version = 19
    }
)

test.run_registered_tests()
