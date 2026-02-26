-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=4, strict=true })
local t_utils = require "integration_test.utils"

-- supported comand classes: SWITCH_BINARY
local switch_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_BINARY},
      {value = zw.SWITCH_MULTILEVEL},
    }
  }
}

local mock_switch = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("switch-level.yml"),
  zwave_endpoints = switch_endpoints
})

local function test_init()
  test.mock_device.add_test_device(mock_switch)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Added lifecycle event should be handled",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_switch.id, "added" },
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock_switch,
          SwitchMultilevel:Get({})
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
        mock_switch.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_switch,
        SwitchMultilevel:Get({})
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

test.run_registered_tests()
