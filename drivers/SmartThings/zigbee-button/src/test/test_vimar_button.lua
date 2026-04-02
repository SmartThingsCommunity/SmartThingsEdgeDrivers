-- Copyright 2024 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local OnOff = clusters.OnOff
local LevelControl = clusters.Level

local button_attr = capabilities.button.button

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("two-buttons-no-fw-update.yml"),
    zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "Vimar",
      model = "RemoteControl_v1.0",
      server_clusters = {0x0000, 0x0003},
      client_clusters = {0x0006, 0x0008}
    }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Remote Control should be handled in added lifecycle event",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.supportedButtonValues({ "pushed", "down_hold", "up" }, { visibility = { displayed = false } })
      )
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.numberOfButtons({ value = 2 }, { visibility = { displayed = false } })
      )
    )

    for button_number = 1, 2 do
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "button" .. button_number,
          capabilities.button.supportedButtonValues({ "pushed", "down_hold", "up" }, { visibility = { displayed = false } })
        )
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "button" .. button_number,
          capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
        )
      )
    end
    test.socket.capability:__expect_send({
      mock_device.id,
      {
        capability_id = "button", component_id = "main",
        attribute_id = "button", state = { value = "pushed" }
      }
    })

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.wait_for_events()
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Button UP (button1) should handle pushed event",
  function()
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, OnOff.server.commands.On.build_test_rx(mock_device) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button1", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Button DOWN (button2) should handle pushed event",
  function()
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, OnOff.server.commands.Off.build_test_rx(mock_device) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button2", button_attr.pushed({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Button UP (button1) should handle down hold and up event",
  function()
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, LevelControl.server.commands.Move.build_test_rx(mock_device, LevelControl.types.MoveStepMode.UP, 255) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button1", button_attr.down_hold({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.down_hold({ state_change = true }))
    )

    test.socket.zigbee:__queue_receive({ mock_device.id, LevelControl.server.commands.Stop.build_test_rx(mock_device) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button1", button_attr.up({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.up({ state_change = true }))
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Button DOWN (button2) should handle down hold and up",
  function()
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, LevelControl.server.commands.Move.build_test_rx(mock_device, LevelControl.types.MoveStepMode.DOWN, 255)  })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button2", button_attr.down_hold({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.down_hold({ state_change = true }))
    )

    test.socket.zigbee:__queue_receive({ mock_device.id, LevelControl.server.commands.Stop.build_test_rx(mock_device) })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button2", button_attr.up({ state_change = true }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", button_attr.up({ state_change = true }))
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Remote Control driver should handle configuration lifecycle",
  function()
    test.wait_for_events()

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")

    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device,
          zigbee_test_utils.mock_hub_eui,
          OnOff.ID)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device,
          zigbee_test_utils.mock_hub_eui,
          LevelControl.ID)
      }
    )

    for _, component in pairs(mock_device.profile.components) do
      local number_of_buttons = component.id == "main" and 2 or 1
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          component.id,
          capabilities.button.supportedButtonValues({ "pushed", "down_hold", "up" }, { visibility = { displayed = true } })
        )
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          component.id,
          capabilities.button.numberOfButtons({ value = number_of_buttons }, { visibility = { displayed = true } })
        )
      )
    end

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
