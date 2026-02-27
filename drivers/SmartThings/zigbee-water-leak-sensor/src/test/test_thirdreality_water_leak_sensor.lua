-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"

local Basic = clusters.Basic
local IASZone = clusters.IASZone --0x0500
local PowerConfiguration = clusters.PowerConfiguration --0x0001

local OLD_DEVICE_SWBUILD_PAYLOAD = 0x17
local NEW_DEVICE_SWBUILD_PAYLOAD = 0x18

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("water-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Third Reality, Inc",
        model = "3RWS18BZ",
        server_clusters = { 0x0001, 0x0500 }
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
  "Added lifecycle should read ApplicationVersion",
  function()
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "added"})
    test.socket.zigbee:__expect_send({mock_device.id, Basic.attributes.ApplicationVersion:read(mock_device)})
  end
)

test.register_coroutine_test(
  "Refresh necessary attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, IASZone.attributes.ZoneStatus:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Battery percentage report (55) should be handled -> 55% for a device with FW <= 0x17 ",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device, OLD_DEVICE_SWBUILD_PAYLOAD)
      }
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 55)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.battery.battery(55))
    )
  end
)

test.register_coroutine_test(
  "Battery percentage report (110) should be handled -> 55% for a device with FW > 0x17 ",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device, NEW_DEVICE_SWBUILD_PAYLOAD)
      }
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 110)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.battery.battery(55))
    )
  end
)

test.register_coroutine_test(
  "Battery percentage report (120) should be handled -> 100% for a device with FW <= 0x17 ",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device, OLD_DEVICE_SWBUILD_PAYLOAD)
      }
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 120)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.battery.battery(100))
    )
  end
)

test.register_coroutine_test(
  "Battery percentage report (240) should be handled -> 100% for a device with FW > 0x17 ",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device, NEW_DEVICE_SWBUILD_PAYLOAD)
      }
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 240)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.battery.battery(100))
    )
  end
)

test.run_registered_tests()
