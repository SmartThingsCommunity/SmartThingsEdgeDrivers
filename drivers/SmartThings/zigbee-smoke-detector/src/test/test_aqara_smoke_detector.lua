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
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"


local PowerConfiguration = clusters.PowerConfiguration
local selfCheck = capabilities["stse.selfCheck"]
local selfCheckId = "stse.selfCheck"


test.add_package_capability("selfCheck.yaml")

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local PRIVATE_MUTE_ATTRIBUTE_ID = 0x0126
local PRIVATE_SELF_CHECK_ATTRIBUTE_ID = 0x0127
local PRIVATE_SMOKE_ZONE_STATUS_ATTRIBUTE_ID = 0x013A



local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("smoke-battery-aqara.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.sensor_smoke.acn03",
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
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.clear()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.audioMute.mute.unmuted()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", selfCheck.selfCheckState.idle()))
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
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PRIVATE_CLUSTER_ID)
    })

    local config_attr_message = zigbee_test_utils.build_attr_config(mock_device,
      PRIVATE_CLUSTER_ID, PRIVATE_SMOKE_ZONE_STATUS_ATTRIBUTE_ID, 0x0001, 0x0E10, data_types.Uint16, 0x0001)
    test.socket.zigbee:__expect_send({mock_device.id, config_attr_message})

    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE,
      data_types.Uint8, 0x01) })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)


test.register_coroutine_test(
  "smokeDetector report should be handled",
  function()
    local attr_report_data = {
      { PRIVATE_SMOKE_ZONE_STATUS_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0001 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.smokeDetector.smoke.detected()))
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
