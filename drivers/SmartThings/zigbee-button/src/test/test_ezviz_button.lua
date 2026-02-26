-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local zb_const = require "st.zigbee.constants"
local messages = require "st.zigbee.messages"
local data_types = require "st.zigbee.data_types"
local zcl_messages = require "st.zigbee.zcl"
local report_attr = require "st.zigbee.zcl.global_commands.report_attribute"

local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration
local ZoneStatusAttribute = IASZone.attributes.ZoneStatus

local EZVIZ_PRIVATE_BUTTON_CLUSTER = 0xFE05
local EZVIZ_PRIVATE_ATTR = 0x0000

local ZIGBEE_ONE_BUTTON_BATTERY = "one-button-battery"

local mock_device_ezviz_button = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition(ZIGBEE_ONE_BUTTON_BATTERY .. ".yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "EZVIZ",
        server_clusters = { 0x0500, 0x0001, 0xFE05, 0xFE00 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device_ezviz_button)end

test.set_test_init_function(test_init)

test.register_message_test(
    "Battery percentage report should be handled (button)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_ezviz_button.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device_ezviz_button, 55) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_ezviz_button:generate_test_message("main", capabilities.battery.battery(28))
      }
    },
    {
       min_api_version = 19
    }
)

local function build_test_attr_report(device, value)
    local report_body = report_attr.ReportAttribute({
      report_attr.ReportAttributeAttributeRecord(EZVIZ_PRIVATE_ATTR, data_types.Uint8.ID, value)
    })
    local zclh = zcl_messages.ZclHeader({
      cmd = data_types.ZCLCommandId(report_body.ID)
    })
    local addrh = messages.AddressHeader(
      device:get_short_address(),
      device.fingerprinted_endpoint_id,
      zb_const.HUB.ADDR,
      zb_const.HUB.ENDPOINT,
      zb_const.HA_PROFILE_ID,
      EZVIZ_PRIVATE_BUTTON_CLUSTER
    )
    local message_body = zcl_messages.ZclMessageBody({
      zcl_header = zclh,
      zcl_body = report_body
    })
    return messages.ZigbeeMessageRx({
      address_header = addrh,
      body = message_body
    })
end

test.register_message_test(
    "EZVIZ private attribute report should result with sending pushed event",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_ezviz_button.id, build_test_attr_report(mock_device_ezviz_button, 0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_ezviz_button:generate_test_message("main", capabilities.button.button.pushed({ state_change = true }))
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "EZVIZ private attribute report should result with sending double event",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_ezviz_button.id, build_test_attr_report(mock_device_ezviz_button, 0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_ezviz_button:generate_test_message("main", capabilities.button.button.double({ state_change = true }))
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "EZVIZ private attribute report should result with sending held event",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device_ezviz_button.id, build_test_attr_report(mock_device_ezviz_button, 0x03) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_ezviz_button:generate_test_message("main", capabilities.button.button.held({ state_change = true }))
      }
    },
    {
       min_api_version = 19
    }
)

-- test.register_coroutine_test(
--     "Health check should check all relevant attributes",
--     function()
--       test.mock_time.advance_time(50000)
--       test.socket.zigbee:__set_channel_ordering("relaxed")
--       test.socket.zigbee:__expect_send({ mock_device_ezviz_button.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_ezviz_button) })
--       test.wait_for_events()
--     end,
--     {
--       test_init = function()
--         test.mock_device.add_test_device(mock_device_ezviz_button)
--         test.timer.__create_and_queue_test_time_advance_timer(30, "interval", "health_check")
--       end
--     }
-- )

test.register_coroutine_test(
    "Refresh necessary attributes",
    function()
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({ mock_device_ezviz_button.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
      test.socket.zigbee:__expect_send(
        {
          mock_device_ezviz_button.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device_ezviz_button)
        }
      )
      test.socket.zigbee:__expect_send({ mock_device_ezviz_button.id, ZoneStatusAttribute:read(mock_device_ezviz_button) })
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device_ezviz_button.id, "added" })
      test.socket.capability:__expect_send(
        mock_device_ezviz_button:generate_test_message(
          "main",
          capabilities.button.supportedButtonValues({ "pushed", "held", "double" }, { visibility = { displayed = false } })
        )
      )
      test.socket.capability:__expect_send(
        mock_device_ezviz_button:generate_test_message(
          "main",
          capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
        )
      )
      test.socket.capability:__expect_send(
        mock_device_ezviz_button:generate_test_message("main", capabilities.button.button.pushed({ state_change = false }))
      )

    end,
    {
       min_api_version = 19
    }
)

test.run_registered_tests()
