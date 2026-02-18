-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local capabilities = require "st.capabilities"
local constants = require "st.zwave.constants"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2})
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local t_utils = require "integration_test.utils"
local version = require "version"
version.api = 10

-- supported command classes: SWITCH_BINARY
local valve_binary_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_BINARY}
    }
  }
}

-- supported command classes: BASIC
local valve_basic_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC}
    }
  }
}

local zwave_valve_profile = t_utils.get_profile_definition("valve-generic.yml")

local mock_valve_binary = test.mock_device.build_test_zwave_device({
  profile = zwave_valve_profile,
  zwave_endpoints = valve_binary_endpoints
})

local mock_valve_basic = test.mock_device.build_test_zwave_device({
  profile = zwave_valve_profile,
  zwave_endpoints = valve_basic_endpoints
})

local function test_init()
  test.mock_device.add_test_device(mock_valve_binary)
  test.mock_device.add_test_device(mock_valve_basic)
end
test.set_test_init_function(test_init)

local zwave_binary_valve_on_report = zw_test_utils.zwave_test_build_receive_command(
  SwitchBinary:Report({current_value=SwitchBinary.value.ON_ENABLE})
)

local zwave_binary_valve_off_report = zw_test_utils.zwave_test_build_receive_command(
  SwitchBinary:Report({current_value=SwitchBinary.value.OFF_DISABLE})
)


test.register_message_test(
    "Binary valve on/off report should be handled: on",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_valve_binary.id, zwave_binary_valve_on_report }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_valve_binary:generate_test_message("main", capabilities.valve.valve.open())
      }
    }
)

test.register_message_test(
    "Binary valve on/off report should be handled: off",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_valve_binary.id, zwave_binary_valve_off_report }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_valve_binary:generate_test_message("main", capabilities.valve.valve.closed())
      }
    }
)

test.register_message_test(
    "Refresh Capability Command should refresh valve Binary device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_valve_binary.id, "added" },
      },
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_valve_binary.id,
          { capability = "refresh", command = "refresh", args = {} }
        }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock_valve_binary,
          SwitchBinary:Get({})
        )
      },
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Refresh Capability Command should refresh Valve(Switch) Basic device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_valve_basic.id, "added" },
      },
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_valve_basic.id,
          { capability = "refresh", command = "refresh", args = {} }
        }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock_valve_basic,
          Basic:Get({})
        )
      },
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_coroutine_test(
    "Setting valve (basic) on should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_valve_basic.id,
            { capability = "valve", command = "open", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_valve_basic,
              Basic:Set({
                          value=SwitchBinary.value.ON_ENABLE
                        })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_valve_basic,
              Basic:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting valve (basic) off should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_valve_basic.id,
            { capability = "valve", command = "close", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_valve_basic,
              Basic:Set({
                          value=SwitchBinary.value.OFF_DISABLE
                        })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_valve_basic,
              Basic:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting valve (binary) on should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_valve_binary.id,
            { capability = "valve", command = "open", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_valve_binary,
              SwitchBinary:Set({
                          target_value=SwitchBinary.value.ON_ENABLE,
                        })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_valve_binary,
              SwitchBinary:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting switch (basic) off should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(constants.DEFAULT_GET_STATUS_DELAY, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_valve_binary.id,
            { capability = "valve", command = "close", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_valve_binary,
              SwitchBinary:Set({
                          target_value=SwitchBinary.value.OFF_DISABLE,
                        })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(constants.DEFAULT_GET_STATUS_DELAY)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_valve_binary,
              SwitchBinary:Get({})
          )
      )
    end
)

test.run_registered_tests()
