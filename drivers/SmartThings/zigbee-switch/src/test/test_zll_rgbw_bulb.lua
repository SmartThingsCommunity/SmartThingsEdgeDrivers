-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local version = require "version"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff
local Level = clusters.Level
local ColorControl = clusters.ColorControl

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("rgbw-bulb.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "AduroSmart Eria",
        model = "ZLL-ExtendedColor",
        server_clusters = { 0x0006, 0x0008, 0x0300 },
        profile_id = 0xC05E,
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
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.attributes.CurrentHue:configure_reporting(mock_device, 1, 3600, 16)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.attributes.CurrentSaturation:configure_reporting(mock_device, 1, 3600, 16)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.attributes.ColorTempPhysicalMaxMireds:configure_reporting(mock_device, 1, 43200, 1)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.attributes.ColorTempPhysicalMinMireds:configure_reporting(mock_device, 1, 43200, 1)
      }
    )
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Refresh necessary attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTempPhysicalMaxMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTempPhysicalMinMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentHue:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentSaturation:read(mock_device) })
  end
)

test.register_coroutine_test(
  "ZLL periodic poll should occur",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTempPhysicalMaxMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTempPhysicalMinMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentHue:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentSaturation:read(mock_device) })
    test.wait_for_events()

    test.mock_time.advance_time(5*60)
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.wait_for_events()
  end,
  {
    test_init = function()
      test.mock_device.add_test_device(mock_device)
      test.timer.__create_and_queue_test_time_advance_timer(5*60, "interval", "polling")
    end
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
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTempPhysicalMaxMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTempPhysicalMinMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentHue:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentSaturation:read(mock_device) })
  end
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
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTempPhysicalMaxMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTempPhysicalMinMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentHue:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentSaturation:read(mock_device) })
  end
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
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTempPhysicalMaxMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTempPhysicalMinMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentHue:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentSaturation:read(mock_device) })
  end
)

test.register_coroutine_test(
  "ColorTemperature command setColorTemperature should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = {200} } })
    if version.api > 15 then mock_device:expect_native_cmd_handler_registration("colorTemperature", "setColorTemperature") end

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.On(mock_device)})
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.commands.MoveToColorTemperature(mock_device, 5000, 0x0000)})

    test.wait_for_events()
    test.mock_time.advance_time(2)

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTempPhysicalMaxMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.ColorTempPhysicalMinMireds:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentHue:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentSaturation:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Set Hue command test",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "colorControl", component = "main", command = "setHue", args = { 50 } } })

    mock_device:expect_native_cmd_handler_registration("colorControl", "setHue")
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.On(mock_device) })

    local hue = math.floor((50 * 0xFE) / 100.0 + 0.5)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.server.commands.MoveToHue(mock_device, hue, 0x00, 0x0000)
      }
    )

    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentHue:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Set Saturation command test",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "colorControl", component = "main", command = "setSaturation", args = { 50 } } })

    mock_device:expect_native_cmd_handler_registration("colorControl", "setSaturation")
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.commands.On(mock_device) })

    local saturation = math.floor((50 * 0xFE) / 100.0 + 0.5)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.server.commands.MoveToSaturation(mock_device, saturation, 0x0000)
      }
    )

    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentSaturation:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Set Color command test",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id, { capability = "colorControl", component = "main", command = "setColor", args = { { hue = 50, saturation = 50 } } } })

    mock_device:expect_native_cmd_handler_registration("colorControl", "setColor")
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.server.commands.On(mock_device) })

    local hue = math.floor((50 * 0xFE) / 100.0 + 0.5)
    local sat = math.floor((50 * 0xFE) / 100.0 + 0.5)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        ColorControl.server.commands.MoveToHueAndSaturation(mock_device, hue, sat, 0x0000)
      }
    )

    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentHue:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ColorControl.attributes.CurrentSaturation:read(mock_device) })
  end
)

test.run_registered_tests()
