-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"
local write_attribute_response = require "st.zigbee.zcl.global_commands.write_attribute_response"
local zcl_messages = require "st.zigbee.zcl"
test.add_package_capability("sensitivityAdjustment.yaml")
test.add_package_capability("detectionFrequency.yaml")

local detectionFrequency = capabilities["stse.detectionFrequency"]

local PowerConfiguration = clusters.PowerConfiguration
local PREF_FREQUENCY_KEY = "prefFrequency"
local PREF_FREQUENCY_VALUE_DEFAULT = 60
local PREF_CHANGED_KEY = "prefChangedKey"
local PREF_CHANGED_VALUE = "prefChangedValue"
local FREQUENCY_ATTRIBUTE_ID = 0x0102
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MOTION_ILLUMINANCE_ATTRIBUTE_ID = 0x0112
local MFG_CODE = 0x115F

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("motion-illuminance-battery-aqara.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.motion.agl02",
        server_clusters = { PRIVATE_CLUSTER_ID, PowerConfiguration.ID }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

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
  "Handle added lifecycle",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.motionSensor.motion.inactive()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.illuminanceMeasurement.illuminance(0)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      detectionFrequency.detectionFrequency(PREF_FREQUENCY_VALUE_DEFAULT, {visibility = {displayed = false}})))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(100)))
  end
)

test.register_coroutine_test(
  "Handle doConfigure lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 3600, 1)
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE
        ,
        data_types.Uint8, 1) })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Reported motion detected including illuminance",
  function()
    local detect_duration = mock_device:get_field(0x0102) or 120
    test.timer.__create_and_queue_test_time_advance_timer(detect_duration, "oneshot")
    local attr_report_data = {
      { MOTION_ILLUMINANCE_ATTRIBUTE_ID, data_types.Int32.ID, 0x0001006E } -- 65646
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    )
    -- 65646-65536=110
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance(110))
    )
    test.mock_time.advance_time(detect_duration)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.motionSensor.motion.inactive()))
  end
)

test.register_coroutine_test(
  "Handle detection frequency capability",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
    { capability = "stse.detectionFrequency", component = "main", command = "setDetectionFrequency", args = {60} } })

    mock_device:set_field(PREF_CHANGED_KEY, PREF_FREQUENCY_KEY)
    mock_device:set_field(PREF_CHANGED_VALUE, PREF_FREQUENCY_VALUE_DEFAULT)

    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, FREQUENCY_ATTRIBUTE_ID, MFG_CODE
        , data_types.Uint8, PREF_FREQUENCY_VALUE_DEFAULT)
    })
  end
)

test.register_coroutine_test(
  "Motion detected twice cancels existing timer and creates a new one",
  function()
    local detect_duration = PREF_FREQUENCY_VALUE_DEFAULT
    -- Pre-register two timers: first will be cancelled, second will fire
    test.timer.__create_and_queue_test_time_advance_timer(detect_duration, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(detect_duration, "oneshot")
    local attr_report_data = {
      { MOTION_ILLUMINANCE_ATTRIBUTE_ID, data_types.Int32.ID, 0x0001006E } -- 65646
    }
    -- First motion event
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance(110))
    )
    test.wait_for_events()
    -- Second motion event before first timer fires - cancels first timer
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance(110))
    )
    test.wait_for_events()
    -- Only the second timer fires
    test.mock_time.advance_time(detect_duration)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.motionSensor.motion.inactive()))
  end
)

test.register_coroutine_test(
  "WriteAttributeResponse with PREF_FREQUENCY_KEY updates detection frequency",
  function()
    mock_device:set_field(PREF_CHANGED_KEY, PREF_FREQUENCY_KEY)
    mock_device:set_field(PREF_CHANGED_VALUE, PREF_FREQUENCY_VALUE_DEFAULT)
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      build_write_attr_res(PRIVATE_CLUSTER_ID, 0x00)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      detectionFrequency.detectionFrequency(PREF_FREQUENCY_VALUE_DEFAULT, {visibility = {displayed = false}})))
  end
)

test.run_registered_tests()
