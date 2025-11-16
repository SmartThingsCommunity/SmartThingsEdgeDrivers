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

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local zb_const = require "st.zigbee.constants"
local zcl_messages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local cluster_base = require "st.zigbee.cluster_base"
local report_attr = require "st.zigbee.zcl.global_commands.report_attribute"

local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"

local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement

local HUMIDITY_CLUSTER_ID = 0xFC45
local HUMIDITY_MEASURE_ATTR_ID = 0x0000

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("humidity-temp-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "CentraLite",
        model = "3310-S",
        server_clusters = { 0x0001, 0x0402, 0xFC45 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Refresh should read all necessary attributes",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        cluster_base.read_manufacturer_specific_attribute(
          mock_device,
          HUMIDITY_CLUSTER_ID,
          HUMIDITY_MEASURE_ATTR_ID,
          0x104E
        )
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        cluster_base.read_manufacturer_specific_attribute(
          mock_device,
          HUMIDITY_CLUSTER_ID,
          HUMIDITY_MEASURE_ATTR_ID,
          0xC2DF
        )
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
      }
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device,
        zigbee_test_utils.mock_hub_eui,
        HUMIDITY_CLUSTER_ID
      )
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device,
        zigbee_test_utils.mock_hub_eui,
        TemperatureMeasurement.ID
      )
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device,
        zigbee_test_utils.mock_hub_eui,
        PowerConfiguration.ID
      )
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 30, 600, 100)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      device_management.attr_config(
        mock_device,
        {
          cluster = 0xFC45,
          attribute = 0x0000,
          minimum_interval = 30,
          maximum_interval = 3600,
          data_type = data_types.Uint16,
          reportable_change = 100,
          mfg_code = 0x104E
        }
      )
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      device_management.attr_config(
        mock_device,
        {
          cluster = 0xFC45,
          attribute = 0x0000,
          minimum_interval = 30,
          maximum_interval = 3600,
          data_type = data_types.Uint16,
          reportable_change = 100,
          mfg_code = 0xC2DF
        }
      )
    })
    test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, TemperatureMeasurement.attributes.MeasuredValue:read(mock_device) })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.read_manufacturer_specific_attribute(
        mock_device,
        HUMIDITY_CLUSTER_ID,
        HUMIDITY_MEASURE_ATTR_ID,
        0x104E
      )
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.read_manufacturer_specific_attribute(
        mock_device,
        HUMIDITY_CLUSTER_ID,
        HUMIDITY_MEASURE_ATTR_ID,
        0xC2DF
      )
    })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

local function build_test_attr_report(device, value)
  local report_body = report_attr.ReportAttribute({
    report_attr.ReportAttributeAttributeRecord(HUMIDITY_MEASURE_ATTR_ID, data_types.Uint16.ID, value)
  })

  local zclh = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(report_body.ID)
  })
  local addrh = messages.AddressHeader(
    device:get_short_address(),
    device.fingerprinted_endpoint_id,
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    zb_const.HA_PROFILE_ID,
    HUMIDITY_CLUSTER_ID
  )
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = report_body
  })
  return messages.ZigbeeMessageRx({
    address_header = addrh,
    body = message_body
  })
end

test.register_message_test(
  "Custom Humidity report should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, build_test_attr_report(mock_device, 7500) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 75 }))
    }
  }
)

test.run_registered_tests()
