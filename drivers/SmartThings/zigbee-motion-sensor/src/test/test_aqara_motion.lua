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
local FREQUENCY_DEFAULT_VALUE = 120

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("motion-illuminance-battery-aqara.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.motion.agl02",
        server_clusters = { 0xFCC0, PowerConfiguration.ID }
      }
    }
  }
)

local mock_high_precision_device = test.mock_device.build_test_zigbee_device(
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
  test.mock_device.add_test_device(mock_high_precision_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Motion sensor: Configure",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.motionSensor.motion.inactive()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.illuminanceMeasurement.illuminance(0)))
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

test.register_coroutine_test(
  "Motion sensor: Reported motion detected including illuminance",
  function()
    local attr_report_data = {
      { 0x0112, data_types.Int32.ID, 0x0001006E } -- 65646
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0xFCCC, attr_report_data, 0x115F)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    )

    -- 65646-65536=110
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance(110))
    )

    test.wait_for_events()

    local detect_duration = mock_device:get_field(0x0102) or 120
    test.mock_time.advance_time(detect_duration)
    test.socket.capability:__expect_send(
      mock_high_precision_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    )
  end
)

test.register_coroutine_test(
  "High Precision Motion Sensor: Configure ",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")

    test.socket.device_lifecycle:__queue_receive({ mock_high_precision_device.id, "added" })
    test.socket.capability:__expect_send(mock_high_precision_device:generate_test_message("main",
      capabilities.motionSensor.motion.inactive()))
    test.socket.capability:__expect_send(mock_high_precision_device:generate_test_message("main",
      detectionFrequency.detectionFrequency(FREQUENCY_DEFAULT_VALUE)))
    test.socket.capability:__expect_send(mock_high_precision_device:generate_test_message("main",
      sensitivityAdjustment.sensitivityAdjustment.Medium()))
    test.socket.capability:__expect_send(mock_high_precision_device:generate_test_message("main",
      capabilities.battery.battery(100)))
    test.wait_for_events()

    test.socket.device_lifecycle:__queue_receive({ mock_high_precision_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_high_precision_device.id,
      zigbee_test_utils.build_bind_request(mock_high_precision_device, zigbee_test_utils.mock_hub_eui,
        OccupancySensing.ID)
    })
    test.socket.zigbee:__expect_send(
      {
        mock_high_precision_device.id,
        OccupancySensing.attributes.Occupancy:configure_reporting(mock_high_precision_device, 30, 3600)
      }
    )
    test.socket.zigbee:__expect_send({
      mock_high_precision_device.id,
      zigbee_test_utils.build_bind_request(mock_high_precision_device, zigbee_test_utils.mock_hub_eui,
        PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send(
      {
        mock_high_precision_device.id,
        PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_high_precision_device, 30, 21600, 1)
      }
    )
    test.socket.zigbee:__expect_send({
      mock_high_precision_device.id,
      zigbee_test_utils.build_bind_request(mock_high_precision_device, zigbee_test_utils.mock_hub_eui,
        PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send(
      {
        mock_high_precision_device.id,
        PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_high_precision_device, 30, 3600, 1)
      }
    )
    test.socket.zigbee:__expect_send({ mock_high_precision_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_high_precision_device, 0xFCC0, 0x0009, 0x115F,
        data_types.Uint8, 1) })
    mock_high_precision_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "High Precision Motion Sensor: Reported motion detected",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__queue_receive(
      {
        mock_high_precision_device.id,
        OccupancySensing.attributes.Occupancy:build_test_attr_report(mock_high_precision_device, 1)
      }
    )
    test.socket.capability:__expect_send(
      mock_high_precision_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    )
    test.wait_for_events()

    local detect_duration = mock_high_precision_device:get_field(0x0102) or 120
    test.mock_time.advance_time(detect_duration)
    test.socket.capability:__expect_send(
      mock_high_precision_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    )
  end
)

test.run_registered_tests()
