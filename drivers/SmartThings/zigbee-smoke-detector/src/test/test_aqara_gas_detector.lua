-- Copyright 2024 SmartThings
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
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"



local selfCheck = capabilities["stse.selfCheck"]
local lifeTimeReport = capabilities["stse.lifeTimeReport"]
local sensitivityAdjustment = capabilities["stse.sensitivityAdjustment"]

local sensitivityAdjustmentId = "stse.sensitivityAdjustment"
local selfCheckId = "stse.selfCheck"

test.add_package_capability("lifeTimeReport.yaml")
test.add_package_capability("selfCheck.yaml")
test.add_package_capability("sensitivityAdjustment.yaml")

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local PRIVATE_SENSITIVITY_ADJUSTMENT_ATTRIBUTE_ID = 0x010C
local PRIVATE_MUTE_ATTRIBUTE_ID = 0x0126
local PRIVATE_SELF_CHECK_ATTRIBUTE_ID = 0x0127
local PRIVATE_LIFE_TIME_ATTRIBUTE_ID = 0x0128
local PRIVATE_GAS_ZONE_STATUS_ATTRIBUTE_ID = 0x013A



local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("gas-lifetime-selfcheck-aqara.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.sensor_gas.acn02",
        server_clusters = { 0x0001, 0xFCC0 }
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
    test.socket.zigbee:__expect_send({ mock_device.id,
    cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE,
    data_types.Uint8, 0x01) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.gasDetector.gas.clear()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.audioMute.mute.unmuted()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", sensitivityAdjustment.sensitivityAdjustment.High()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", selfCheck.selfCheckState.idle()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", lifeTimeReport.lifeTimeState.normal()))
  end
)



test.register_coroutine_test(
  "gasDetector report should be handled",
  function()
    local attr_report_data = {
      { PRIVATE_GAS_ZONE_STATUS_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0001 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.gasDetector.gas.detected()))
  end
)



test.register_coroutine_test(
  "audioMute report should be handled",
  function()
    local attr_report_data = {
      { PRIVATE_MUTE_ATTRIBUTE_ID, data_types.Uint8.ID, 0x01 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.audioMute.mute.muted()))
  end
)



test.register_coroutine_test(
  "Capability on command should be handled : device mute",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "audioMute", component = "main", command = "mute", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id,
    cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
    PRIVATE_MUTE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 1) })
  end
)



test.register_coroutine_test(
  "selfCheck report should be handled",
  function()
    local attr_report_data = {
      { PRIVATE_SELF_CHECK_ATTRIBUTE_ID, data_types.Uint8.ID, 0x01 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    selfCheck.selfCheckState.selfCheckCompleted()))
  end
)



test.register_coroutine_test(
  "Capability on command should be handled : device selfCheck",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = selfCheckId, component = "main", command = "startSelfCheck", args = {state = "selfCheckCompleted"} } })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",selfCheck.selfCheckState.selfChecking()))
    test.socket.zigbee:__expect_send({ mock_device.id,
    cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
    PRIVATE_SELF_CHECK_ATTRIBUTE_ID, MFG_CODE, data_types.Boolean, true) })
  end
)



test.register_coroutine_test(
  "lifetime report should be handled",
  function()
    local attr_report_data = {
      { PRIVATE_LIFE_TIME_ATTRIBUTE_ID, data_types.Uint8.ID, 0x01 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    lifeTimeReport.lifeTimeState.endOfLife()))
  end
)



test.register_coroutine_test(
  "sensitivityAdjustment report should be handled",
  function()
    local attr_report_data = {
      { PRIVATE_SENSITIVITY_ADJUSTMENT_ATTRIBUTE_ID, data_types.Uint8.ID, 0x01 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    sensitivityAdjustment.sensitivityAdjustment.Low()))
  end
)



test.register_coroutine_test(
  "Capability on command should be handled : setSensitivityAdjustment Low",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = sensitivityAdjustmentId, component = "main", command = "setSensitivityAdjustment", args = {"Low"}}} )
    test.socket.zigbee:__expect_send({ mock_device.id,
    cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
    PRIVATE_SENSITIVITY_ADJUSTMENT_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x01) })
  end
)



test.run_registered_tests()
