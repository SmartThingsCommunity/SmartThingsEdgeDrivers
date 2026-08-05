-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local IASZone = clusters.IASZone
local PRIVATE_CMD_ID = 0xF1

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("one-button-battery-no-fw-update.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "MultIR",
        model = "MIR-SO100",
        server_clusters = {0x0000, 0x0001, 0x0003, 0x0020, 0x0500, 0x0B05}
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
  "added lifecycle event",
  function()
    -- The initial button pushed event should be send during the device's first time onboarding
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.supportedButtonValues({ "pushed","held","double" }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send({
      mock_device.id,
      {
        capability_id = "button", component_id = "main",
        attribute_id = "button", state = { value = "pushed" }
      }
    })
    -- Avoid sending the initial button pushed event after driver switch-over, as the switch-over event itself re-triggers the added lifecycle.
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.supportedButtonValues({ "pushed","held","double" }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
      )
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_message_test(
    "IASZone cmd 0xF1 0x00 are handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, IASZone.ID, PRIVATE_CMD_ID, 0x0000, "\x00", 0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.button.button.pushed({state_change = true}))
      }
    }
)

test.register_message_test(
    "IASZone cmd 0xF1 0x01 are handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, IASZone.ID, PRIVATE_CMD_ID, 0x0000, "\x01", 0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.button.button.double({state_change = true}))
      }
    }
)

test.register_message_test(
    "IASZone cmd 0xF1 0x80 are handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, zigbee_test_utils.build_custom_command_id(mock_device, IASZone.ID, PRIVATE_CMD_ID, 0x0000, "\x80", 0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.button.button.held({state_change = true}))
      }
    }
)

test.run_registered_tests()
