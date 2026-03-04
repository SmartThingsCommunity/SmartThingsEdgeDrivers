-- Copyright 2024 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"


local MULTISTATE_INPUT_CLUSTER_ID = 0x0012
local PRESENT_ATTRIBUTE_ID = 0x0055
local PowerConfiguration = clusters.PowerConfiguration

local MFG_CODE = 0x115F
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID_T1 = 0x0009
local PRIVATE_ATTRIBUTE_ID_E1 = 0x0125
local PRIVATE_ATTRIBUTE_ID_ALIVE = 0x00F7
local MODE_CHANGE = "stse.allowOperationModeChange"

local COMP_LIST = { "button1", "button2", "all" }

local mock_device_h1_single = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("aqara-single-button-mode.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.remote.b18ac1",
        server_clusters = { 0x0001, 0x0012 }
      }
    }
  }
)

local mock_device_e1 = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("one-button-batteryLevel.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.remote.acn003",
        server_clusters = { 0x0001, 0x0012 }
      }
    }
  }
)

local mock_device_h1_double_rocker = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("aqara-double-buttons-mode.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.remote.b286acn03",
        server_clusters = { 0x0001, 0x0012 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device_h1_single)
  test.mock_device.add_test_device(mock_device_e1)
  test.mock_device.add_test_device(mock_device_h1_double_rocker)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle added lifecycle - T1 double rocker",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_h1_double_rocker.id, "added" })
    test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message("main",
      capabilities.button.supportedButtonValues({ "pushed", "held", "double" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message("main",
      capabilities.button.numberOfButtons({ value = 1 })))
    test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message("main",
      capabilities.button.button.pushed({ state_change = false })))
    test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message("main",
      capabilities.batteryLevel.battery.normal()))
    test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message("main",
      capabilities.batteryLevel.type("CR2032")))
    test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message("main",
      capabilities.batteryLevel.quantity(1)))
    for i = 1, 3 do
      test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message(COMP_LIST[i],
        capabilities.button.supportedButtonValues({ "pushed", "held", "double" }, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message(COMP_LIST[i],
        capabilities.button.numberOfButtons({ value = 1 })))
      test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message(COMP_LIST[i],
        capabilities.button.button.pushed({ state_change = false })))
    end
  end
)

test.register_coroutine_test(
  "Handle doConfigure lifecycle -- e1",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_e1.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_device_e1.id,
      zigbee_test_utils.build_bind_request(mock_device_e1, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device_e1.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device_e1, 30, 3600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device_e1.id,
      zigbee_test_utils.build_bind_request(mock_device_e1, zigbee_test_utils.mock_hub_eui, MULTISTATE_INPUT_CLUSTER_ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device_e1.id,
      zigbee_test_utils.build_attr_config(mock_device_e1, MULTISTATE_INPUT_CLUSTER_ID, PRESENT_ATTRIBUTE_ID, 0x0003,
        0x1C20, data_types.Uint16, 0x0001)
    })
    test.socket.zigbee:__expect_send({ mock_device_e1.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device_e1, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID_E1,
        MFG_CODE,
        data_types.Uint8, 2) })
    mock_device_e1:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)


test.register_coroutine_test(
  "Handle doConfigure lifecycle -- t1",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_h1_double_rocker.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_device_h1_double_rocker.id,
      zigbee_test_utils.build_bind_request(mock_device_h1_double_rocker, zigbee_test_utils.mock_hub_eui,
        PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device_h1_double_rocker.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device_h1_double_rocker, 30, 3600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device_h1_double_rocker.id,
      zigbee_test_utils.build_bind_request(mock_device_h1_double_rocker, zigbee_test_utils.mock_hub_eui,
        MULTISTATE_INPUT_CLUSTER_ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device_h1_double_rocker.id,
      zigbee_test_utils.build_attr_config(mock_device_h1_double_rocker, MULTISTATE_INPUT_CLUSTER_ID, PRESENT_ATTRIBUTE_ID,
        0x0003, 0x1C20, data_types.Uint16, 0x0001)
    })
    test.socket.zigbee:__expect_send({ mock_device_h1_double_rocker.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device_h1_double_rocker, PRIVATE_CLUSTER_ID,
        PRIVATE_ATTRIBUTE_ID_T1, MFG_CODE,
        data_types.Uint8, 1) })
    mock_device_h1_double_rocker:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Reported button should be handled: pushed true",
  function()
    local attr_report_data = {
      { PRESENT_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0001 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device_h1_double_rocker.id,
      zigbee_test_utils.build_attribute_report(mock_device_h1_double_rocker, MULTISTATE_INPUT_CLUSTER_ID,
        attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message("main",
      capabilities.button.button.pushed({ state_change = true })))
    test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message("button1",
      capabilities.button.button.pushed({ state_change = true })))
  end
)

test.register_coroutine_test(
  "Reported button should be handled: double true",
  function()
    local attr_report_data = {
      { PRESENT_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0002 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device_h1_double_rocker.id,
      zigbee_test_utils.build_attribute_report(mock_device_h1_double_rocker, MULTISTATE_INPUT_CLUSTER_ID,
        attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message("main",
      capabilities.button.button.double({ state_change = true })))
    test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message("button1",
      capabilities.button.button.double({ state_change = true })))
  end
)

test.register_coroutine_test(
  "Reported button should be handled: held true",
  function()
    local attr_report_data = {
      { PRESENT_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0000 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device_h1_double_rocker.id,
      zigbee_test_utils.build_attribute_report(mock_device_h1_double_rocker, MULTISTATE_INPUT_CLUSTER_ID,
        attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message("main",
      capabilities.button.button.held({ state_change = true })))
    test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message("button1",
      capabilities.button.button.held({ state_change = true })))
  end
)

test.register_message_test(
  "Battery Level - Normal",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device_e1.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device_e1, 30) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_e1:generate_test_message("main", capabilities.batteryLevel.battery("normal"))
    }
  }
)
test.register_message_test(
  "Battery Level - Warning",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device_e1.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device_e1, 27) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_e1:generate_test_message("main", capabilities.batteryLevel.battery("warning"))
    }
  }
)
test.register_message_test(
  "Battery Level - Critical",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device_e1.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device_e1, 20) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_e1:generate_test_message("main", capabilities.batteryLevel.battery("critical"))
    }
  }
)

test.register_coroutine_test(
  "Wireless Remote Switch H1 Mode Change",
  function()
    local mode = 2
    local updates = {
      preferences = {
        [MODE_CHANGE] = true
      }
    }
    test.socket.device_lifecycle:__queue_receive(mock_device_h1_double_rocker:generate_info_changed(updates))
    mock_device_h1_double_rocker:set_field("devicemode", 1, { persist = true })
    local attr_report_data = {
      { PRIVATE_ATTRIBUTE_ID_ALIVE, data_types.OctetString.ID, "\x01\x21\xB8\x0B\x03\x28\x19\x04\x21\xA8\x13\x05\x21\x45\x08\x06\x24\x07\x00\x00\x00\x00\x08\x21\x15\x01\x0A\x21\xF5\x65\x0C\x20\x01\x64\x20\x01\x66\x20\x03\x67\x20\x01\x68\x21\xA8\x00" }
    }
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({
      mock_device_h1_double_rocker.id,
      zigbee_test_utils.build_attribute_report(mock_device_h1_double_rocker, PRIVATE_CLUSTER_ID, attr_report_data,
        MFG_CODE)
    })
    test.socket.zigbee:__expect_send({ mock_device_h1_double_rocker.id, cluster_base
        .write_manufacturer_specific_attribute(mock_device_h1_double_rocker, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID_E1,
          MFG_CODE, data_types.Uint8, mode) })
    test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message("main",
      capabilities.button.supportedButtonValues({ "pushed", "held", "double" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message("main",
      capabilities.button.numberOfButtons({ value = 1 })))
    test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message("main",
      capabilities.button.button.pushed({ state_change = false })))

    for i = 1, 3 do
      test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message(COMP_LIST[i],
        capabilities.button.supportedButtonValues({ "pushed", "held", "double" }, { visibility = { displayed = false } })))
      test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message(COMP_LIST[i],
        capabilities.button.numberOfButtons({ value = 1 })))
      test.socket.capability:__expect_send(mock_device_h1_double_rocker:generate_test_message(COMP_LIST[i],
        capabilities.button.button.pushed({ state_change = false })))
    end
  end
)

test.register_coroutine_test(
  "Handle added lifecycle - H1 single rocker (sets mode=1)",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_h1_single.id, "added" })
    test.socket.capability:__expect_send(mock_device_h1_single:generate_test_message("main",
      capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device_h1_single:generate_test_message("main",
      capabilities.button.numberOfButtons({ value = 1 })))
    test.socket.capability:__expect_send(mock_device_h1_single:generate_test_message("main",
      capabilities.button.button.pushed({ state_change = false })))
    test.socket.capability:__expect_send(mock_device_h1_single:generate_test_message("main",
      capabilities.batteryLevel.battery.normal()))
    test.socket.capability:__expect_send(mock_device_h1_single:generate_test_message("main",
      capabilities.batteryLevel.type("CR2450")))
    test.socket.capability:__expect_send(mock_device_h1_single:generate_test_message("main",
      capabilities.batteryLevel.quantity(1)))
  end
)

test.run_registered_tests()
