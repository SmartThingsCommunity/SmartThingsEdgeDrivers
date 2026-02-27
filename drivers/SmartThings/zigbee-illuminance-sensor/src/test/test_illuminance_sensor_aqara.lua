-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"
local write_attribute_response = require "st.zigbee.zcl.global_commands.write_attribute_response"
local zcl_messages = require "st.zigbee.zcl"
test.add_package_capability("detectionFrequency.yaml")

local IlluminanceMeasurement = clusters.IlluminanceMeasurement
local PowerConfiguration = clusters.PowerConfiguration

local detectionFrequency = capabilities["stse.detectionFrequency"]

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local FREQUENCY_ATTRIBUTE_ID = 0x0000

local FREQUENCY_DEFAULT_VALUE = 5
local FREQUENCY_PREF = "frequencyPref"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("battery-illuminance-aqara.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.sen_ill.agl01",
        server_clusters = { 0x0400, 0x0001 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle added lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.illuminanceMeasurement.illuminance(0)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      detectionFrequency.detectionFrequency(FREQUENCY_DEFAULT_VALUE, {visibility = {displayed = false}})))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(100)))
  end
)

test.register_coroutine_test(
  "Handle doConfigure lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        IlluminanceMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 3600, 7200, 1)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 3600, 1)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, IlluminanceMeasurement.ID)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
      }
    )

    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE
        , data_types.Uint8, 1) })

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_message_test(
  "Illuminance report should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        IlluminanceMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 21370)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.illuminanceMeasurement.illuminance({ value = 137 }))
    }
  }
)

test.register_message_test(
  "BatteryVoltage report should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 30)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
    }
  }
)

local function build_write_attr_res(cluster, status)
  local addr_header = messages.AddressHeader(
    mock_device:get_short_address(),
    mock_device.fingerprinted_endpoint_id,
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    zb_const.HA_PROFILE_ID,
    cluster
  )
  local write_attribute_body = write_attribute_response.WriteAttributeResponse(status, {})
  local zcl_header = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(write_attribute_body.ID)
  })
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zcl_header,
    zcl_body = write_attribute_body
  })
  return messages.ZigbeeMessageRx({
    address_header = addr_header,
    body = message_body
  })
end

test.register_coroutine_test(
  "Handle setDetectionFrequency capability command",
  function()
    local frequency = 10
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "stse.detectionFrequency", component = "main", command = "setDetectionFrequency", args = { frequency } } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, FREQUENCY_ATTRIBUTE_ID,
        MFG_CODE, data_types.Uint16, frequency) })
  end
)

test.register_coroutine_test(
  "Handle write attr res on PRIVATE_CLUSTER_ID emits detectionFrequency",
  function()
    mock_device:set_field(FREQUENCY_PREF, FREQUENCY_DEFAULT_VALUE)
    test.socket.zigbee:__queue_receive({ mock_device.id,
      build_write_attr_res(PRIVATE_CLUSTER_ID, 0x00) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      detectionFrequency.detectionFrequency(FREQUENCY_DEFAULT_VALUE, { visibility = { displayed = false } })))
  end
)

test.run_registered_tests()
