-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Basic = (require "st.zwave.CommandClass.Basic")({version=1,strict=true})
local t_utils = require "integration_test.utils"

local generic_zwave_device1_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC}
    }
  }
}

local mock_zwave_device1 = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("switch-level.yml"),
  zwave_endpoints = generic_zwave_device1_endpoints
})

local function test_init()
  test.mock_device.add_test_device(mock_zwave_device1)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Added lifecycle event should be handled",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_zwave_device1.id, "added" },
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock_zwave_device1,
          Basic:Get({})
        )
      }
    },
    {
      inner_block_ordering = "relaxed"
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
  "Refresh Capability Command should refresh Switch device",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_zwave_device1.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_zwave_device1,
        Basic:Get({})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Basic REPORT 0xFF should be handled as switch on",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zwave_device1.id,
        zw_test_utils.zwave_test_build_receive_command(Basic:Report({value = 0xFF}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zwave_device1:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_zwave_device1.id, capability_id = "switch", capability_attr_id = "switch" }
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zwave_device1:generate_test_message("main", capabilities.switchLevel.level(100))
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_zwave_device1.id, capability_id = "switchLevel", capability_attr_id = "level" }
      }
    },
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Basic REPORT 0x00 should be handled as switch off",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zwave_device1.id,
        zw_test_utils.zwave_test_build_receive_command(Basic:Report({value = 0x00}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zwave_device1:generate_test_message("main", capabilities.switch.switch.off())
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_zwave_device1.id, capability_id = "switch", capability_attr_id = "switch" }
      }
    },
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Basic REPORT 0x31 should be handled as switch on, level(49)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zwave_device1.id,
        zw_test_utils.zwave_test_build_receive_command(Basic:Report({value = 0x31}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zwave_device1:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_zwave_device1.id, capability_id = "switch", capability_attr_id = "switch" }
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zwave_device1:generate_test_message("main", capabilities.switchLevel.level(49))
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_zwave_device1.id, capability_id = "switchLevel", capability_attr_id = "level" }
      }
    },
  },
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Switch capability off commands should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_zwave_device1.id,
      { capability = "switch", command = "off", args = {} }
    })
    mock_zwave_device1:expect_native_cmd_handler_registration("switch", "off")
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zwave_device1,
        Basic:Set({ value = 0x00 })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zwave_device1,
        Basic:Get({})
      )
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Switch capability on commands should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_zwave_device1.id,
      { capability = "switch", command = "on", args = {} }
    })
    mock_zwave_device1:expect_native_cmd_handler_registration("switch", "on")
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zwave_device1,
        Basic:Set({ value = 0xFF })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zwave_device1,
        Basic:Get({})
      )
    )
  end,
  {
     min_api_version = 19
  }
)

local level = 49
test.register_coroutine_test(
  "SwitchLevel capability setLevel commands should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_zwave_device1.id,
      { capability = "switchLevel", command = "setLevel", args = { level } }
    })
    mock_zwave_device1:expect_native_cmd_handler_registration("switchLevel", "setLevel")
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zwave_device1,
        Basic:Set({ value = 0x31 })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zwave_device1,
        Basic:Get({})
      )
    )
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
