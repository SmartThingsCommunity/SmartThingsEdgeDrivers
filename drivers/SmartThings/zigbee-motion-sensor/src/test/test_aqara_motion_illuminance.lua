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

local detectionFrequency = capabilities["stse.detectionFrequency"]

local PowerConfiguration = clusters.PowerConfiguration
local PREF_FREQUENCY_VALUE_DEFAULT = 60
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
      capabilities.illuminanceMeasurement.illuminance(0)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      detectionFrequency.detectionFrequency(PREF_FREQUENCY_VALUE_DEFAULT)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(100)))

    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE
        ,
        data_types.Uint8, 1) })
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

test.run_registered_tests()
