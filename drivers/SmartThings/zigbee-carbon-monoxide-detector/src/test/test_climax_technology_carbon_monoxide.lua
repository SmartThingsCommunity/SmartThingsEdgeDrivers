-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("carbonMonoxide-battery.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "ClimaxTechnology",
          model = "CO_00.00.00.22TC",
          server_clusters = {0x0000}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end
test.set_test_init_function(test_init)

test.register_message_test(
    "added lifecycle event should get initial state for device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_device.id, "added"}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)


test.run_registered_tests()
