-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local OnOff = clusters.OnOff
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_simple_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("switch-power-energy.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "REXENSE",
          model = "HY0105",
          server_clusters = {0x0003, 0x000A, 0x0019}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_simple_device)end

test.set_test_init_function(test_init)


test.register_message_test(
    "Capability command On should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, OnOff.server.commands.On(mock_simple_device) }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, OnOff.server.commands.On(mock_simple_device):to_endpoint(0x02) }
      }
    }
)

test.register_message_test(
    "Capability command Off should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, OnOff.server.commands.Off(mock_simple_device) }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, OnOff.server.commands.Off(mock_simple_device):to_endpoint(0x02) }
      }
    }
)

test.run_registered_tests()
