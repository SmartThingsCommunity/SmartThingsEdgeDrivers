-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local INTERLOCK_ATTRIBUTE_ID = 0x02D0
local DEVICE_MODE_ATTRIBUTE_ID = 0x0289
local POWER_OFF_MEMORY_ATTRIBUTE_ID = 0x0517
local PULSE_INTERVAL_ATTRIBUTE_ID = 0x00EB
local ELECTRIC_SWITCH_TYPE_ATTRIBUTE_ID = 0x000A
local CHANGE_TO_WIRELESS_SWITCH_ATTRIBUTE_ID = 0x0200

local PRIVATE_MODE = "PRIVATE_MODE"

local SUPPORTED_INTERLOCK = { "normal", "interlock" }
local SUPPORTED_DEVICE_MODE = { "wet_contact_mode", "dry_contact_closed_pulse_mode", "dry_contact_on_off_mode" }

-- acn047 (Dual Relay Module T2) runs on standard clusters (never Aqara private mode)
local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("aqara-dual-relay-module-unified.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Aqara",
        model = "lumi.switch.acn047",
        server_clusters = { OnOff.ID, ElectricalMeasurement.ID, SimpleMetering.ID }
      }
    }
  }
)

-- acn047 reports children = 2, so a single child device (relay 2) exists on the second endpoint
local mock_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("aqara-switch-child.yml"),
  device_network_id = string.format("%04X:%02X", mock_device:get_short_address(), 2),
  parent_device_id = mock_device.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_child)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "added: child is reused, button info reported, power/energy restored (0.0 on first add) and no private write",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.numberOfButtons({ value = 2 },
      { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("interlock",
      capabilities.mode.supportedModes(SUPPORTED_INTERLOCK, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("devicemode",
      capabilities.mode.supportedModes(SUPPORTED_DEVICE_MODE, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.supportedButtonValues({ "pushed" },
      { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.button.pushed({ state_change = false })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 0.0, unit = "W" })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 0.0, unit = "Wh" })))
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "refresh reads OnOff, power/energy (standard clusters) and the interlock/devicemode attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, ElectricalMeasurement.attributes.ActivePower:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, INTERLOCK_ATTRIBUTE_ID, MFG_CODE) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, DEVICE_MODE_ATTRIBUTE_ID, MFG_CODE) })
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "switch on command : parent device",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "switch", component = "main", command = "on", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.server.commands.On(mock_device) })
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "switch off command : child device (endpoint 2)",
  function()
    test.socket.capability:__queue_receive({ mock_child.id,
      { capability = "switch", component = "main", command = "off", args = {} } })
    mock_child:expect_native_cmd_handler_registration("switch", "off")
    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.server.commands.Off(mock_device):to_endpoint(0x02) })
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "power meter report (standard ElectricalMeasurement cluster)",
  function()
    mock_device:set_field(PRIVATE_MODE, 0, { persist = true })
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_device, 100)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 10.0, unit = "W" }))
    )
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "interlock attribute report updates the interlock component",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, {
        { INTERLOCK_ATTRIBUTE_ID, data_types.Boolean.ID, true }
      }, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("interlock",
      capabilities.mode.mode("interlock")))
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "device mode attribute report updates the devicemode component",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, {
        { DEVICE_MODE_ATTRIBUTE_ID, data_types.Uint8.ID, 1 }
      }, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("devicemode",
      capabilities.mode.mode("dry_contact_closed_pulse_mode")))
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "setMode on the interlock component writes the interlock attribute",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "mode", component = "interlock", command = "setMode", args = { "interlock" } } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, INTERLOCK_ATTRIBUTE_ID,
        MFG_CODE, data_types.Boolean, true) })
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "setMode on the devicemode component (on/off) writes device value 3",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "mode", component = "devicemode", command = "setMode", args = { "dry_contact_on_off_mode" } } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, DEVICE_MODE_ATTRIBUTE_ID,
        MFG_CODE, data_types.Uint8, 3) })
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "preference powerOffMemory is written on infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.powerOffMemory"] = "on" }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        POWER_OFF_MEMORY_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0) })
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "preference pulseInterval is written on infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.pulseIntervalSetting"] = 500 }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        PULSE_INTERVAL_ATTRIBUTE_ID, MFG_CODE, data_types.Uint16, 500) })
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "preference switchType (nc) is written on infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.switchType"] = "nc" }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        ELECTRIC_SWITCH_TYPE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0) })
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "preference changeToWirelessSwitch is written on infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.changeToWirelessSwitch"] = true }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        CHANGE_TO_WIRELESS_SWITCH_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0) })
  end,
  {
    min_api_version = 17
  }
)

test.run_registered_tests()
