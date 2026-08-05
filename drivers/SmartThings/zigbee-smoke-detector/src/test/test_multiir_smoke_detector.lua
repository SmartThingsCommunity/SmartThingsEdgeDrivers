-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local IASZone = clusters.IASZone

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("smoke-battery-tamper-no-fw-update.yml"),
    zigbee_endpoints = {
      [0x01] = {
        id = 0x01,
        manufacturer = "MultIR",
        model = "MIR-SM200",
        server_clusters = { 0x0001,0x0020, 0x0500, 0x0502 }
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
  "Handle added lifecycle",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.battery.battery(100)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.smokeDetector.smoke.clear()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.tamperAlert.tamper.clear()))
  end,
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Reported ZoneStatus should be handled: smoke/clear tamper/clear",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0000) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Reported ZoneStatus should be handled: smoke/detected tamper/detected",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0005) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Reported ZoneStatus should be handled: smoke/tested tamper/detected",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0006) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.tested())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "ZoneStatusChangeNotification should be handled: smoke/detected tamper/detected",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0005, 0x00) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "ZoneStatusChangeNotification should be handled: smoke/tested tamper/detected",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0006, 0x00) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.tested())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "ZoneStatusChangeNotification should be handled: smoke/clear tamper/clear",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0000, 0x00) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    }
  },
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
