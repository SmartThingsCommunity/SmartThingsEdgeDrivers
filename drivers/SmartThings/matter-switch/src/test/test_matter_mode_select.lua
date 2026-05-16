-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local ModeSelect = require "embedded_clusters.ModeSelect"

local MOCK_MODE_SELECT_EP = 1
local MOCK_MODE_SELECT_CLUSTER_ID = ModeSelect.ID

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("switch-binary-mode.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = 0x001D, cluster_type = "SERVER"}, -- Descriptor
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = 0x0006, cluster_type = "SERVER"},  -- OnOff
        {
          cluster_id = MOCK_MODE_SELECT_CLUSTER_ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0
        },
      },
      device_types = {
        {device_type_id = 0x0103, device_type_revision = 1} -- On/Off Light Switch
      }
    }
  }
})

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)


test.register_coroutine_test(
  "SupportedModes report should generate supportedModes and supportedArguments events",
  function()
    -- Build a SupportedModes report with 3 modes
    local supported_modes_data = {
      {
        label = "Normal",
        mode = 0,
        semantic_tags = {}
      },
      {
        label = "Eco",
        mode = 1,
        semantic_tags = {}
      },
      {
        label = "Turbo",
        mode = 2,
        semantic_tags = {}
      },
    }

    test.socket.matter:__queue_receive({
      mock_device.id,
      ModeSelect.attributes.SupportedModes:build_test_report_data(
        mock_device, MOCK_MODE_SELECT_EP, supported_modes_data
      )
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.mode.supportedModes({"Normal", "Eco", "Turbo"}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.mode.supportedArguments({"Normal", "Eco", "Turbo"}, { visibility = { displayed = false } })
      )
    )
  end
)


test.register_coroutine_test(
  "CurrentMode report should generate mode event with correct label",
  function()
    -- Pre-populate supported modes on the device
    mock_device:set_field("__mode_select_supported_modes", {{0, "Normal"}, {1, "Eco"}, {2, "Turbo"}}, { persist = true })

    test.socket.matter:__queue_receive({
      mock_device.id,
      ModeSelect.attributes.CurrentMode:build_test_report_data(
        mock_device, MOCK_MODE_SELECT_EP, 1
      )
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.mode.mode("Eco")
      )
    )
  end
)


test.register_message_test(
  "setMode command should send ChangeToMode with correct mode index",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "mode", component = "main", command = "setMode", args = { "Turbo" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        ModeSelect.commands.ChangeToMode(mock_device, MOCK_MODE_SELECT_EP, 2)
      }
    }
  },
  {
    test_init = function()
      test.disable_startup_messages()
      test.mock_device.add_test_device(mock_device)
      mock_device:set_field("__mode_select_supported_modes", {{0, "Normal"}, {1, "Eco"}, {2, "Turbo"}}, { persist = true })
    end
  }
)


test.run_registered_tests()
