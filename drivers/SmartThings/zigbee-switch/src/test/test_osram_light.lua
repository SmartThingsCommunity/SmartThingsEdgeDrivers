-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local clusters = require "st.zigbee.zcl.clusters"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"

local OnOff = clusters.OnOff
local Level = clusters.Level

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("on-off-level.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "OSRAM",
        model = "LIGHTIFY A19 ON/OFF/DIM",
        server_clusters = {0x0006, 0x0008}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Configure should configure all necessary attributes and refresh device",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")

    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, OnOff.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Level.ID)
    })

    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        OnOff.attributes.OnOff:configure_reporting(mock_device, 0, 300, 1)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        Level.attributes.CurrentLevel:configure_reporting(mock_device, 0, 300, 1)
      }
    )

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Device added lifecycle event should be handled",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",capabilities.switchLevel.level(100)))
  end,
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Refresh should read all necessary attributes",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {mock_device.id, {capability = "refresh", component = "main", command = "refresh", args = {}}}
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        OnOff.attributes.OnOff:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        Level.attributes.CurrentLevel:read(mock_device)
      }
    }
  },
  {
    inner_block_ordering = "relaxed"
  },
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
