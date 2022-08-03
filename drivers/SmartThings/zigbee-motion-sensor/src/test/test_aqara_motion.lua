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
local test = require "integration_test"
test.add_package_capability("sensitivityAdjustment.yaml")
test.add_package_capability("detectionFrequency.yaml")

local sensitivityAdjustment = capabilities["stse.sensitivityAdjustment"]
local detectionFrequency = capabilities["stse.detectionFrequency"]

local PowerConfiguration = clusters.PowerConfiguration
local OccupancySensing = clusters.OccupancySensing
local FREQUENCY_DEFAULT_VALUE = 120

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("motion-battery-aqara.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.motion.agl02",
        server_clusters = { 0x0406, 0x0001, 0xFCC0 }
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
  "Configure should configure all necessary attributes",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.motionSensor.motion.inactive()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      sensitivityAdjustment.sensitivityAdjustment.Medium()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      detectionFrequency.detectionFrequency(FREQUENCY_DEFAULT_VALUE)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.battery.battery(100)))
    test.wait_for_events()

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, OccupancySensing.ID)
    })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        OccupancySensing.attributes.Occupancy:configure_reporting(mock_device, 30, 3600)
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1)
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 3600, 1)
      }
    )
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, 0xFCC0, 0x0009, 0x115F, data_types.Uint8, 1) })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_message_test(
  "Reported motion should be handled: active",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, OccupancySensing.attributes.Occupancy:build_test_attr_report(mock_device, 0x01) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    }
  }
)

test.register_message_test(
  "Reported motion should be handled: inactive",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, OccupancySensing.attributes.Occupancy:build_test_attr_report(mock_device, 0x00) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    }
  }
)

test.run_registered_tests()
