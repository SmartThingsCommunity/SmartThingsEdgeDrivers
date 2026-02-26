-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local constants = require "st.zwave.constants"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2})
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local t_utils = require "integration_test.utils"

-- supported comand classes: SWITCH_BINARY
local switch_binary_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_BINARY}
    }
  }
}

-- supported comand classes: BASIC
local switch_basic_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC}
    }
  }
}

local zwave_switch_profile = t_utils.get_profile_definition("switch-binary.yml")

local mock_switch_binary = test.mock_device.build_test_zwave_device({
  profile = zwave_switch_profile,
  zwave_endpoints = switch_binary_endpoints
})

local mock_switch_basic = test.mock_device.build_test_zwave_device({
  profile = zwave_switch_profile,
  zwave_endpoints = switch_basic_endpoints
})

local function test_init()
  test.mock_device.add_test_device(mock_switch_binary)
  test.mock_device.add_test_device(mock_switch_basic)
end
test.set_test_init_function(test_init)

local zwave_binary_switch_on_report = zw_test_utils.zwave_test_build_receive_command(
  SwitchBinary:Report({current_value=SwitchBinary.value.ON_ENABLE})
)

local zwave_binary_switch_off_report = zw_test_utils.zwave_test_build_receive_command(
  SwitchBinary:Report({current_value=SwitchBinary.value.OFF_DISABLE})
)


test.register_message_test(
    "Binary switch on/off report should be handled: on",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_switch_binary.id, zwave_binary_switch_on_report }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_switch_binary:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_switch_binary.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "Binary switch on/off report should be handled: off",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_switch_binary.id, zwave_binary_switch_off_report }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_switch_binary:generate_test_message("main", capabilities.switch.switch.off())
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_switch_binary.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    },
    {
       min_api_version = 19
    }
)


test.register_message_test(
    "Added lifecycle event should be handled",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_switch_binary.id, "added" },
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock_switch_binary,
          SwitchBinary:Get({})
        )
      },
    },
    {
      inner_block_ordering = "relaxed"
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
  "Refresh Capability Command should refresh Switch Binary device",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_switch_binary.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_switch_binary,
        SwitchBinary:Get({})
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
    "Added lifecycle event should be handled",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_switch_basic.id, "added" },
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock_switch_basic,
          Basic:Get({})
        )
      },
    },
    {
      inner_block_ordering = "relaxed"
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
  "Refresh Capability Command should refresh Switch Basic device",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_switch_basic.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_switch_basic,
        Basic:Get({})
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  },
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
    "Setting switch (basic) on should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_switch_basic.id,
            { capability = "switch", command = "on", args = {} }
          }
      )
      mock_switch_basic:expect_native_cmd_handler_registration("switch", "on")
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_switch_basic,
              Basic:Set({
                          value=SwitchBinary.value.ON_ENABLE
                        })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_switch_basic,
              Basic:Get({})
          )
      )
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "Setting switch (basic) off should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_switch_basic.id,
            { capability = "switch", command = "off", args = {} }
          }
      )
      mock_switch_basic:expect_native_cmd_handler_registration("switch", "off")
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_switch_basic,
              Basic:Set({
                          value=SwitchBinary.value.OFF_DISABLE
                        })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_switch_basic,
              Basic:Get({})
          )
      )
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "Setting switch (binary) on should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_switch_binary.id,
            { capability = "switch", command = "on", args = {} }
          }
      )
      mock_switch_binary:expect_native_cmd_handler_registration("switch", "on")
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_switch_binary,
              SwitchBinary:Set({
                          target_value=SwitchBinary.value.ON_ENABLE,
                        })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_switch_binary,
              SwitchBinary:Get({})
          )
      )
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "Setting switch (basic) off should generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(constants.DEFAULT_GET_STATUS_DELAY, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_switch_binary.id,
            { capability = "switch", command = "off", args = {} }
          }
      )
      mock_switch_binary:expect_native_cmd_handler_registration("switch", "off")
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_switch_binary,
              SwitchBinary:Set({
                          target_value=SwitchBinary.value.OFF_DISABLE,
                        })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(constants.DEFAULT_GET_STATUS_DELAY)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_switch_binary,
              SwitchBinary:Get({})
          )
      )
    end,
    {
       min_api_version = 19
    }
)

test.run_registered_tests()
