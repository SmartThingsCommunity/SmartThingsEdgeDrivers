-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local Basic = clusters.Basic

local function build_device(profile, manufacturer, model)
  return test.mock_device.build_test_zigbee_device({
    profile = t_utils.get_profile_definition(profile),
    zigbee_endpoints = {
      [0x01] = {
        id = 0x01,
        manufacturer = manufacturer or "SONOFF",
        model = model or "Dongle-LMG21",
        server_clusters = { Basic.ID },
      },
    },
  })
end

local mock_device = build_device("range-extender-signal.yml")
local base_device = build_device("range-extender.yml")
local other_manufacturer = build_device("range-extender-signal.yml", "Other manufacturer")
local other_model = build_device("range-extender-signal.yml", "SONOFF", "Other model")

local function read_response(device, lqi, rssi)
  local message = Basic.attributes.ZCLVersion:build_test_read_attr_response(device, 3)
  message.lqi = data_types.Uint8(lqi)
  message.rssi = data_types.Int8(rssi)
  return message
end

local function expect_signal_strength(device, lqi, rssi)
  test.socket.capability:__expect_send(device:generate_test_message(
    "main", capabilities.signalStrength.lqi(lqi)))
  test.socket.capability:__expect_send(device:generate_test_message(
    "main", capabilities.signalStrength.rssi({ value = rssi, unit = "dBm" })))
end

local function base_test_init()
  test.mock_device.add_test_device(base_device)
end

zigbee_test_utils.prepare_zigbee_env_info()
test.set_test_init_function(function()
  test.mock_device.add_test_device(mock_device)
end)

test.register_coroutine_test(
  "Refresh reads the device and publishes received signal strength",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} },
    })
    test.socket.zigbee:__expect_send({ mock_device.id, Basic.attributes.ZCLVersion:read(mock_device) })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, read_response(mock_device, 203, -67) })
    expect_signal_strength(mock_device, 203, -67)
  end,
  {
    min_api_version = 17,
  }
)

test.register_coroutine_test(
  "Configuration obtains an initial signal sample without configuring reporting",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({ mock_device.id, Basic.attributes.ZCLVersion:read(mock_device) })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, read_response(mock_device, 169, -74) })
    expect_signal_strength(mock_device, 169, -74)
  end,
  {
    min_api_version = 17,
  }
)

test.register_coroutine_test(
  "Health polling obtains new signal samples every five minutes",
  function()
    test.wait_for_events()
    test.mock_time.advance_time(300)
    test.socket.zigbee:__expect_send({ mock_device.id, Basic.attributes.ZCLVersion:read(mock_device) })
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({ mock_device.id, read_response(mock_device, 211, -61) })
    expect_signal_strength(mock_device, 211, -61)
    test.wait_for_events()

    test.mock_time.advance_time(300)
    test.socket.zigbee:__expect_send({ mock_device.id, Basic.attributes.ZCLVersion:read(mock_device) })
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({ mock_device.id, read_response(mock_device, 83, -91) })
    expect_signal_strength(mock_device, 83, -91)
  end,
  {
    min_api_version = 17,
    test_init = function()
      test.mock_device.add_test_device(mock_device)
      test.timer.__create_and_queue_test_time_advance_timer(300, "interval", 2)
    end,
  }
)

test.register_coroutine_test(
  "Zero LQI and zero dBm are preserved in received samples",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, read_response(mock_device, 0, 0) })
    expect_signal_strength(mock_device, 0, 0)
  end,
  {
    min_api_version = 17,
  }
)

test.register_coroutine_test(
  "Signal strength preserves Zigbee metadata boundary values",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, read_response(mock_device, 255, -128) })
    expect_signal_strength(mock_device, 255, -128)
  end,
  {
    min_api_version = 17,
  }
)

test.register_coroutine_test(
  "Unsolicited Basic reports also update signal strength",
  function()
    local report = Basic.attributes.ZCLVersion:build_test_attr_report(mock_device, 3)
    report.lqi = data_types.Uint8(127)
    report.rssi = data_types.Int8(-82)
    test.socket.zigbee:__queue_receive({ mock_device.id, report })
    expect_signal_strength(mock_device, 127, -82)
  end,
  {
    min_api_version = 17,
  }
)

test.register_coroutine_test(
  "Initializing a base profile does not automatically add signal strength capabilities",
  function()
    test.wait_for_events()
  end,
  {
    min_api_version = 17,
    test_init = base_test_init,
  }
)

test.register_coroutine_test(
  "Samples are not published for a base profile without signal strength",
  function()
    test.socket.zigbee:__queue_receive({ base_device.id, read_response(base_device, 196, -70) })
  end,
  {
    min_api_version = 17,
    test_init = base_test_init,
  }
)

test.register_coroutine_test(
  "Changing to the signal strength profile obtains and publishes an initial sample",
  function()
    test.socket.device_lifecycle:__queue_receive(base_device:generate_info_changed({
      profile = t_utils.get_profile_definition("range-extender-signal.yml"),
    }))
    test.socket.zigbee:__expect_send({ base_device.id, Basic.attributes.ZCLVersion:read(base_device) })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ base_device.id, read_response(base_device, 184, -72) })
    expect_signal_strength(base_device, 184, -72)
  end,
  {
    min_api_version = 17,
    test_init = base_test_init,
  }
)

test.register_coroutine_test(
  "Initializing or changing preferences does not request another signal sample",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ preferences = {} }))
  end,
  {
    min_api_version = 17,
  }
)

for _, case in ipairs({
  { name = "a different manufacturer with the supported model", device = other_manufacturer },
  { name = "a different model with the supported manufacturer", device = other_model },
}) do
  local device = case.device
  test.register_coroutine_test(
    "Signal strength subdriver rejects " .. case.name,
    function()
      test.socket.zigbee:__queue_receive({ device.id, read_response(device, 196, -70) })
    end,
    {
      min_api_version = 17,
      test_init = function()
        test.mock_device.add_test_device(device)
      end,
    }
  )
end

test.run_registered_tests()
