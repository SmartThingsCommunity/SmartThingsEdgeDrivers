-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local cluster_base = require "st.zigbee.cluster_base"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local generic_body = require "st.zigbee.generic_body"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local messages = require "st.zigbee.messages"
local zcl_messages = require "st.zigbee.zcl"
local zb_const = require "st.zigbee.constants"

local Basic = clusters.Basic
local Thermostat = clusters.Thermostat
local MFG_CODE = 0x1286
local PRIVATE_CLUSTER = 0xFC11

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("thermostat-sonoff.yml"),
  preferences = {
    temperatureCompensation = 0,
    childLock = false,
    bluetoothPairingBroadcast = false,
    openWindowDetection = false,
    frostProofTemperature = 5,
    temporaryModeAction = "exit",
    temporaryModeDuration = 30,
    temporaryModeTemperature = 30,
    temperatureThresholdLow = -2,
    temperatureThresholdHigh = 2,
    radarSensitivity = "2",
    radarDoNotDisturb = false,
    radarDoNotDisturbStart = 0,
    radarDoNotDisturbEnd = 0,
    screenWorkingBrightness = 5,
    screenStandbyBrightness = 0,
    screenNightStandbyBrightness = 0,
    screenNightMode = false,
    screenNightStart = 0,
    screenNightEnd = 0,
    relayHeatingNormallyClosed = false,
    relayBoilerNormallyClosed = false,
    overheatProtectionTemperature = 33.5,
    overheatProtection = false,
    radarEnabled = false,
  },
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "SONOFF",
      model = "TP-WGZBA",
      server_clusters = { Basic.ID, Thermostat.ID, PRIVATE_CLUSTER },
    },
  },
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  -- Register the device before every test so the SONOFF sub-driver is selected.
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

-- Builds the cluster-specific temporary-mode command expected from a preference update.
local function build_temporary_mode_command(payload)
  -- The command uses the same manufacturer cluster endpoint as private attribute writes.
  local header = zcl_messages.ZclHeader({ cmd = data_types.ZCLCommandId(0x11) })
  header.frame_ctrl:set_cluster_specific()
  return messages.ZigbeeMessageTx({
    address_header = messages.AddressHeader(
      zb_const.HUB.ADDR, zb_const.HUB.ENDPOINT, mock_device:get_short_address(),
      mock_device:get_endpoint(PRIVATE_CLUSTER), zb_const.HA_PROFILE_ID, PRIVATE_CLUSTER
    ),
    body = zcl_messages.ZclMessageBody({ zcl_header = header, zcl_body = generic_body.GenericBody(payload) }),
  })
end

test.register_coroutine_test(
  "SONOFF sub-driver should match only TP-WGZBA",
  function()
    -- The flattened handler owns the fingerprint without a nested TP-WGZBA dispatcher.
    local can_handle = require "sonoff.can_handle"
    assert(can_handle({}, nil, mock_device))
    local rejected = can_handle({}, nil, {
      get_manufacturer = function() return "SONOFF" end,
      get_model = function() return "OTHER" end,
    })
    assert(not rejected)
  end
)

test.register_message_test(
  "Refresh should read only standard capability attributes",
  {
    { channel = "capability", direction = "receive", message = { mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } } },
    { channel = "zigbee", direction = "send", message = { mock_device.id, Thermostat.attributes.LocalTemperature:read(mock_device) } },
    { channel = "zigbee", direction = "send", message = { mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device) } },
    { channel = "zigbee", direction = "send", message = { mock_device.id, Thermostat.attributes.SystemMode:read(mock_device) } },
    { channel = "zigbee", direction = "send", message = { mock_device.id, Thermostat.attributes.ThermostatRunningState:read(mock_device) } },
    { channel = "zigbee", direction = "send", message = { mock_device.id, Basic.attributes.SWBuildID:read(mock_device) } },
  }
)

test.register_coroutine_test(
  "Configure should bind and enable standard thermostat reporting",
  function()
    -- All visible state is now maintained by standard reporting instead of custom capabilities.
    test.socket.zigbee:__set_channel_ordering("relaxed")
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({ mock_device.id, zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Thermostat.ID) })
    test.socket.zigbee:__expect_send({ mock_device.id, Thermostat.attributes.LocalTemperature:configure_reporting(mock_device, 10, 300, 10) })
    test.socket.zigbee:__expect_send({ mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(mock_device, 10, 300, 50) })
    test.socket.zigbee:__expect_send({ mock_device.id, Thermostat.attributes.SystemMode:configure_reporting(mock_device, 10, 300) })
    test.socket.zigbee:__expect_send({ mock_device.id, Thermostat.attributes.ThermostatRunningState:configure_reporting(mock_device, 10, 300, 1) })
  end
)

test.register_coroutine_test(
  "Changing preferences should write typed private attributes and structures",
  function()
    -- Settings are sent through infoChanged rather than custom capability commands.
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { openWindowDetection = true, temperatureThresholdLow = -1.5, temperatureThresholdHigh = 1.5 },
    }))
    test.socket.zigbee:__expect_send({ mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER, 0x6000, MFG_CODE, data_types.Boolean, true) })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER, 0x601F, MFG_CODE, data_types.Structure,
        data_types.Structure({ data_types.Int16(-150), data_types.Int16(150) }))
    })
  end
)

test.register_coroutine_test(
  "Temporary-mode preference should send the vendor cluster command",
  function()
    -- Timer mode carries the selected duration and temperature as little-endian values.
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { temporaryModeAction = "timer", temporaryModeDuration = 45, temporaryModeTemperature = 28.5 },
    }))
    test.socket.zigbee:__expect_send({ mock_device.id, build_temporary_mode_command("\x02\x8C\x0A\x00\x00\x22\x0B") })
  end
)

test.register_coroutine_test(
  "Setting thermostat mode should read SystemMode after the write",
  function()
    -- Readback provides a reliable app update when the device does not report mode changes.
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.thermostatMode.ID, component = "main", command = "heat", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, Thermostat.attributes.SystemMode:write(mock_device, Thermostat.attributes.SystemMode.HEAT) })
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id, Thermostat.attributes.SystemMode:read(mock_device) })
  end
)

test.register_message_test(
  "Decoded standard reports should publish standard thermostat events",
  {
    { channel = "zigbee", direction = "receive", message = { mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 2350) } },
    { channel = "capability", direction = "send", message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 23.5, unit = "C" })) },
    { channel = "zigbee", direction = "receive", message = { mock_device.id, Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, Thermostat.attributes.SystemMode.AUTO) } },
    { channel = "capability", direction = "send", message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.auto()) },
  }
)

test.run_registered_tests()
