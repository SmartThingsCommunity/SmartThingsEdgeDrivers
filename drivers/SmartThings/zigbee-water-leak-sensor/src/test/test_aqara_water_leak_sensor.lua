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
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration
local ZoneStatusAttribute = IASZone.attributes.ZoneStatus

local MFG_CODE = 0x115F
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("water-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.flood.agl02",
        server_clusters = { 0x0001, 0x0500 }
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
  "Handle added lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.waterSensor.water.dry()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(100)))

    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE
        ,
        data_types.Uint8, 1) })
  end
)

test.register_message_test(
  "Reported water should be handled: wet",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, ZoneStatusAttribute:build_test_attr_report(mock_device, 0x0001) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.waterSensor.water.wet())
    }
  }
)

test.register_message_test(
  "Reported water should be handled: dry",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, ZoneStatusAttribute:build_test_attr_report(mock_device, 0x0000) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.waterSensor.water.dry())
    }
  }
)

test.register_message_test(
  "Battery voltage report should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 30) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
    }
  }
)

test.run_registered_tests()
