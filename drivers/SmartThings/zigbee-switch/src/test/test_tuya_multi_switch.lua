-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local OnOff = clusters.OnOff
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_simple_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("switch-3.yml"),
      fingerprinted_endpoint_id = 0x01
    }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_simple_device)end

test.set_test_init_function(test_init)

test.register_message_test(
    "Reported on off status should be handled: on ep 1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_simple_device,
                                                                                                true):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("switch1",  capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled: on ep 2",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_simple_device,
                                                                                                true):from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("switch2",  capabilities.switch.switch.on())
      }
    }
)
test.register_message_test(
    "Reported on off status should be handled: on ep 3",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_simple_device,
                                                                                                true):from_endpoint(0x03) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("switch3",  capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled: off ep 1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_simple_device,
                                                                                                false):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("switch1",  capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Capability command switch on should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "switch", component = "switch3", command = "on", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, OnOff.server.commands.On(mock_simple_device):to_endpoint(0x03) }
      }
    }
)


test.run_registered_tests()
