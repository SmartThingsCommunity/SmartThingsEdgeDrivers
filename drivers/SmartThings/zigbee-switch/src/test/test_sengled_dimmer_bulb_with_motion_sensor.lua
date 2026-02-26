-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local version = require "version"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff
local Level = clusters.Level
local IASZone = clusters.IASZone

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("on-off-level-motion-sensor.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "sengled",
        model = "E13-N11",
        server_clusters = { 0x0006, 0x0008, 0x0500 },
        profile_id = 0xC05E
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
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, IASZone.ID)
    })

    test.socket.zigbee:__expect_send({
      mock_device.id,
      OnOff.attributes.OnOff:configure_reporting(mock_device, 0, 300, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Level.attributes.CurrentLevel:configure_reporting(mock_device, 1, 3600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASZone.attributes.ZoneStatus:configure_reporting(mock_device, 30, 300, 1)
    })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Added lifecycle should be handlded",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, IASZone.attributes.ZoneStatus:read(mock_device) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Refresh necessary attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, IASZone.attributes.ZoneStatus:read(mock_device) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Capability 'switch' command 'on' should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "switch", component = "main", command = "on", args = {} } })
    if version.api > 15 then mock_device:expect_native_cmd_handler_registration("switch", "on") end

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.On(mock_device) })

    test.wait_for_events()
    test.mock_time.advance_time(2)

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, IASZone.attributes.ZoneStatus:read(mock_device) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Capability 'switch' command 'off' should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "switch", component = "main", command = "off", args = {} } })
    if version.api > 15 then mock_device:expect_native_cmd_handler_registration("switch", "off") end

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.Off(mock_device) })

    test.wait_for_events()
    test.mock_time.advance_time(2)

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, IASZone.attributes.ZoneStatus:read(mock_device) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Capability 'switchLevel' command 'setLevel' on should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 57 } } })
    if version.api > 15 then mock_device:expect_native_cmd_handler_registration("switchLevel", "setLevel") end

    test.socket.zigbee:__expect_send({ mock_device.id, Level.server.commands.MoveToLevelWithOnOff(mock_device, 144, 0xFFFF) })

    test.wait_for_events()
    test.mock_time.advance_time(2)

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, IASZone.attributes.ZoneStatus:read(mock_device) })
  end,
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Reported motion should be handled: active",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0001) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "motionSensor", capability_attr_id = "motion" }
      }
    },
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Reported motion should be handled: inactive",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0000) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "motionSensor", capability_attr_id = "motion" }
      }
    },
  },
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
