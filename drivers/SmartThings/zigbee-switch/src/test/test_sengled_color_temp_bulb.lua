-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff
local Level = clusters.Level
local ColorControl = clusters.ColorControl

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("color-temp-bulb.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "sengled",
        model = "Z01-A19NAE26",
        server_clusters = {0x0006, 0x0008, 0x0300}
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
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, ColorControl.ID)
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
        Level.attributes.CurrentLevel:configure_reporting(mock_device, 1, 3600, 1)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.attributes.ColorTemperatureMireds:configure_reporting(mock_device, 1, 3600, 16)
      }
    )

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTempPhysicalMaxMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTempPhysicalMinMireds:read(mock_device) })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
     min_api_version = 17
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
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        ColorControl.attributes.ColorTemperatureMireds:read(mock_device)
      }
    }
  },
  {
    inner_block_ordering = "relaxed",
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Set Color Temperature command test",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = { 200 } } })

    local temp_in_mired = math.floor(1000000 / 200)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        OnOff.commands.On(mock_device)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.commands.MoveToColorTemperature(mock_device, temp_in_mired, 0x0000)
      }
    )

    test.wait_for_events()

    test.mock_time.advance_time(1)
    test.socket.zigbee:__expect_send({mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device)})
  end,
  {
     min_api_version = 17
  }
)

local TRANSITION_TIME = 3
local OPTIONS_MASK = 0x01
local IGNORE_COMMAND_IF_OFF = 0x00
local REPORTED_MIRED_MIN = 160
local REPORTED_MIRED_MAX = 370

test.register_coroutine_test(
  "Step Color Temperature command with device-reported mired range test",
  function()
    -- Report non-default range values to verify subsequent step commands do not use defaults.
    test.socket.zigbee:__queue_receive({mock_device.id, ColorControl.attributes.ColorTempPhysicalMaxMireds:build_test_attr_report(mock_device, REPORTED_MIRED_MAX)})
    test.socket.zigbee:__queue_receive({mock_device.id, ColorControl.attributes.ColorTempPhysicalMinMireds:build_test_attr_report(mock_device, REPORTED_MIRED_MIN)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.colorTemperature.colorTemperatureRange({minimum = 2703, maximum = 6250})))
    test.wait_for_events()

    test.socket.capability:__queue_receive({mock_device.id, { capability = "statelessColorTemperatureStep", component = "main", command = "stepColorTemperatureByPercent", args = { 20 } } })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.server.commands.StepColorTemperature(mock_device, ColorControl.types.CcStepMode.DOWN, 42, TRANSITION_TIME, REPORTED_MIRED_MIN, REPORTED_MIRED_MAX, OPTIONS_MASK, IGNORE_COMMAND_IF_OFF)
      }
    )
  end,
  {
    min_api_version = 19
  }
)

test.register_coroutine_test(
  "Step Level command test",
  function()
    test.socket.capability:__queue_receive({mock_device.id, { capability = "statelessSwitchLevelStep", component = "main", command = "stepLevel", args = { 25 } } })

    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        Level.commands.Step(mock_device, Level.types.MoveStepMode.UP, 64, TRANSITION_TIME, OPTIONS_MASK, IGNORE_COMMAND_IF_OFF)
       }
     )
    test.wait_for_events()
  end,
  {
    min_api_version = 19
  }
)

test.run_registered_tests()
