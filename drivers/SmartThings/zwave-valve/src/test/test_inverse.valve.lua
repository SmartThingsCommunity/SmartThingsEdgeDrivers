-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2})
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })

local fortrezz_valve_endpoints = {
  {
    command_classes = {
      { value = zw.SWITCH_BINARY },
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("valve-generic.yml"),
  zwave_endpoints = fortrezz_valve_endpoints,
  zwave_manufacturer_id = 0x0084,
  zwave_product_type = 0x0243,
  zwave_product_id = 0x0300
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Binary valve on/off report should be handled: on",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report({current_value=SwitchBinary.value.ON_ENABLE})
        ) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.valve.valve.closed())
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "Binary valve on/off report should be handled: off",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report({current_value=SwitchBinary.value.OFF_DISABLE})
        ) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.valve.valve.open())
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "Basic valve on/off report should be handled: off",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
          Basic:Report({value=SwitchBinary.value.OFF_DISABLE})
        ) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.valve.valve.open())
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "Basic valve on/off report should be handled: on",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
          Basic:Report({value=SwitchBinary.value.ON_ENABLE})
        ) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.valve.valve.closed())
      }
    },
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "Turning valve on should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
            { capability = "valve", command = "open", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              SwitchBinary:Set({
                          target_value=SwitchBinary.value.OFF_DISABLE,
                        })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              SwitchBinary:Get({})
          )
      )
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "Turning valve off should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
            { capability = "valve", command = "close", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              SwitchBinary:Set({
                          target_value=SwitchBinary.value.ON_ENABLE,
                        })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              SwitchBinary:Get({})
          )
      )
    end,
    {
       min_api_version = 19
    }
)

test.run_registered_tests()
