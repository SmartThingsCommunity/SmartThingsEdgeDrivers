-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
test.add_package_capability("sensitivityAdjustment.yaml")
test.add_package_capability("detectionFrequency.yaml")

local sensitivityAdjustment = capabilities["stse.sensitivityAdjustment"]
local detectionFrequency = capabilities["stse.detectionFrequency"]

local PowerConfiguration = clusters.PowerConfiguration
local OccupancySensing = clusters.OccupancySensing
local PREF_FREQUENCY_KEY = "prefFrequency"
local PREF_FREQUENCY_VALUE_DEFAULT = 60
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local PREF_CHANGED_KEY = "prefChangedKey"
local PREF_CHANGED_VALUE = "prefChangedValue"
local PREF_SENSITIVITY_KEY = "prefSensitivity"
local PREF_SENSITIVITY_VALUE_HIGH = 3
local PREF_SENSITIVITY_VALUE_MEDIUM = 2
local PREF_SENSITIVITY_VALUE_LOW = 1
local SENSITIVITY_ATTRIBUTE_ID = 0x010C
local MFG_CODE = 0x115F

-- Needed for building ConfigureReportingResponse msg
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"
local write_attribute_response = require "st.zigbee.zcl.global_commands.write_attribute_response"
local zcl_messages = require "st.zigbee.zcl"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("motion-battery-aqara.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.motion.agl04",
        server_clusters = { OccupancySensing.ID, PowerConfiguration.ID }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle added lifecycle",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.motionSensor.motion.inactive()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      detectionFrequency.detectionFrequency(PREF_FREQUENCY_VALUE_DEFAULT, {visibility = {displayed = false}})))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      sensitivityAdjustment.sensitivityAdjustment.Medium()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.battery.battery(100)))
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
  "Reported motion detected",
  function()
    local detect_duration = mock_device:get_field(0x0102) or 120
    test.timer.__create_and_queue_test_time_advance_timer(detect_duration, "oneshot")
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        OccupancySensing.attributes.Occupancy:build_test_attr_report(mock_device, 1)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    )
    test.mock_time.advance_time(detect_duration)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    )
  end
)

test.register_coroutine_test(
  "Handle occupancy attr",
  function()
    local detect_duration = mock_device:get_field(0x0102) or 120
    test.timer.__create_and_queue_test_time_advance_timer(detect_duration, "oneshot")
    local attr_report_data = {
      { OccupancySensing.attributes.Occupancy.ID, data_types.Int32.ID, 0x0001 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, OccupancySensing.ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    )

    test.mock_time.advance_time(detect_duration)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.motionSensor.motion.inactive()))
  end
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
  "Handle write attr res: detectionFrequency",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      build_write_attr_res(PRIVATE_CLUSTER_ID, 0x00)
    })
    mock_device:set_field(PREF_CHANGED_KEY, PREF_FREQUENCY_KEY)
    mock_device:set_field(PREF_CHANGED_VALUE, PREF_FREQUENCY_VALUE_DEFAULT)
    local value = mock_device:get_field(PREF_CHANGED_VALUE) or 0
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    detectionFrequency.detectionFrequency(value, {visibility = {displayed = false}})))
  end
)

test.register_coroutine_test(
  "Handle write attr res: sensitivityAdjustment High",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      build_write_attr_res(PRIVATE_CLUSTER_ID, 0x00)
    })
    mock_device:set_field(PREF_CHANGED_KEY, PREF_SENSITIVITY_KEY)
    mock_device:set_field(PREF_CHANGED_VALUE, PREF_SENSITIVITY_VALUE_HIGH)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      sensitivityAdjustment.sensitivityAdjustment.High()))
  end
)

test.register_coroutine_test(
  "Handle write attr res: sensitivityAdjustment Medium",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      build_write_attr_res(PRIVATE_CLUSTER_ID, 0x00)
    })
    mock_device:set_field(PREF_CHANGED_KEY, PREF_SENSITIVITY_KEY)
    mock_device:set_field(PREF_CHANGED_VALUE, PREF_SENSITIVITY_VALUE_MEDIUM)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      sensitivityAdjustment.sensitivityAdjustment.Medium()))
  end
)

test.register_coroutine_test(
  "Handle write attr res: sensitivityAdjustment Low",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      build_write_attr_res(PRIVATE_CLUSTER_ID, 0x00)
    })
    mock_device:set_field(PREF_CHANGED_KEY, PREF_SENSITIVITY_KEY)
    mock_device:set_field(PREF_CHANGED_VALUE, PREF_SENSITIVITY_VALUE_LOW)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      sensitivityAdjustment.sensitivityAdjustment.Low()))
  end
)

test.register_coroutine_test(
  "Handle sensitivity adjustment capability",
  function()
    mock_device:set_field(PREF_CHANGED_KEY, PREF_SENSITIVITY_KEY)
    mock_device:set_field(PREF_CHANGED_VALUE, PREF_SENSITIVITY_VALUE_HIGH)
    test.socket.capability:__queue_receive({ mock_device.id,
    { capability = "stse.sensitivityAdjustment", component = "main", command = "setSensitivityAdjustment", args = {"High"} } })

    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, SENSITIVITY_ATTRIBUTE_ID, MFG_CODE
        , data_types.Uint8, PREF_SENSITIVITY_VALUE_HIGH)
    })

    mock_device:set_field(PREF_CHANGED_KEY, PREF_SENSITIVITY_KEY)
    mock_device:set_field(PREF_CHANGED_VALUE, PREF_SENSITIVITY_VALUE_MEDIUM)
    test.socket.capability:__queue_receive({ mock_device.id,
    { capability = "stse.sensitivityAdjustment", component = "main", command = "setSensitivityAdjustment", args = {"Medium"} } })

    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, SENSITIVITY_ATTRIBUTE_ID, MFG_CODE
        , data_types.Uint8, PREF_SENSITIVITY_VALUE_MEDIUM)
    })

    mock_device:set_field(PREF_CHANGED_KEY, PREF_SENSITIVITY_KEY)
    mock_device:set_field(PREF_CHANGED_VALUE, PREF_SENSITIVITY_VALUE_LOW)
    test.socket.capability:__queue_receive({ mock_device.id,
    { capability = "stse.sensitivityAdjustment", component = "main", command = "setSensitivityAdjustment", args = {"Low"} } })

    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, SENSITIVITY_ATTRIBUTE_ID, MFG_CODE
        , data_types.Uint8, PREF_SENSITIVITY_VALUE_LOW)
    })
  end
)

test.run_registered_tests()
