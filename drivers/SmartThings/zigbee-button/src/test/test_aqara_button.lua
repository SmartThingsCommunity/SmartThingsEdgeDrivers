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


local MULTISTATE_INPUT_CLUSTER_ID = 0x0012
local PRESENT_ATTRIBUTE_ID = 0x0055
local PowerConfiguration = clusters.PowerConfiguration

local MFG_CODE = 0x115F
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID_T1 = 0x0009
local PRIVATE_ATTRIBUTE_ID_E1 = 0x0125

local mock_device_e1 = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("one-button-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.remote.acn003",
        server_clusters = { 0x0001, 0x0012 }
      }
    }
  }
)

local mock_device_t1 = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("one-button-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.remote.b1acn02",
        server_clusters = { 0x0001, 0x0012 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device_e1)
  test.mock_device.add_test_device(mock_device_t1)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle added lifecycle -- e1",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_e1.id, "added" })
    test.socket.capability:__expect_send(mock_device_e1:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed","held","double"}, {visibility = { displayed = false }})))
    test.socket.capability:__expect_send(mock_device_e1:generate_test_message("main", capabilities.button.numberOfButtons({value = 1})))
    test.socket.capability:__expect_send(mock_device_e1:generate_test_message("main", capabilities.button.button.pushed({state_change = false})))
    test.socket.capability:__expect_send(mock_device_e1:generate_test_message("main", capabilities.battery.battery(100)))
  end
)

test.register_coroutine_test(
  "Handle added lifecycle -- t1",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_t1.id, "added" })
    test.socket.capability:__expect_send(mock_device_t1:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed","held","double"}, {visibility = { displayed = false }})))
    test.socket.capability:__expect_send(mock_device_t1:generate_test_message("main", capabilities.button.numberOfButtons({value = 1})))
    test.socket.capability:__expect_send(mock_device_t1:generate_test_message("main", capabilities.button.button.pushed({state_change = false})))
    test.socket.capability:__expect_send(mock_device_t1:generate_test_message("main", capabilities.battery.battery(100)))
  end
)

test.register_coroutine_test(
  "Handle doConfigure lifecycle -- e1",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_e1.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_device_e1.id,
      zigbee_test_utils.build_bind_request(mock_device_e1, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device_e1.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device_e1, 30, 3600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device_e1.id,
      zigbee_test_utils.build_bind_request(mock_device_e1, zigbee_test_utils.mock_hub_eui, MULTISTATE_INPUT_CLUSTER_ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device_e1.id,
      zigbee_test_utils.build_attr_config(mock_device_e1, MULTISTATE_INPUT_CLUSTER_ID, PRESENT_ATTRIBUTE_ID, 0x0003, 0x1C20, data_types.Uint16, 0x0001)
    })
    test.socket.zigbee:__expect_send({ mock_device_e1.id,
     cluster_base.write_manufacturer_specific_attribute(mock_device_e1, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID_E1, MFG_CODE,
     data_types.Uint8, 2) })
     mock_device_e1:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)


test.register_coroutine_test(
  "Handle doConfigure lifecycle -- t1",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_t1.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_device_t1.id,
      zigbee_test_utils.build_bind_request(mock_device_t1, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device_t1.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device_t1, 30, 3600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device_t1.id,
      zigbee_test_utils.build_bind_request(mock_device_t1, zigbee_test_utils.mock_hub_eui, MULTISTATE_INPUT_CLUSTER_ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device_t1.id,
      zigbee_test_utils.build_attr_config(mock_device_t1, MULTISTATE_INPUT_CLUSTER_ID, PRESENT_ATTRIBUTE_ID, 0x0003, 0x1C20, data_types.Uint16, 0x0001)
    })
    test.socket.zigbee:__expect_send({ mock_device_t1.id,
     cluster_base.write_manufacturer_specific_attribute(mock_device_t1, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID_T1, MFG_CODE,
     data_types.Uint8, 1) })
     mock_device_t1:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Reported button should be handled: pushed true",
  function()
    local attr_report_data = {
      { PRESENT_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0001 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device_e1.id,
      zigbee_test_utils.build_attribute_report(mock_device_e1, MULTISTATE_INPUT_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device_e1:generate_test_message("main",
    capabilities.button.button.pushed({state_change = true})))
  end
)

test.register_coroutine_test(
  "Reported button should be handled: double true",
  function()
    local attr_report_data = {
      { PRESENT_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0002 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device_e1.id,
      zigbee_test_utils.build_attribute_report(mock_device_e1, MULTISTATE_INPUT_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device_e1:generate_test_message("main",
    capabilities.button.button.double({state_change = true})))
  end
)

test.register_coroutine_test(
  "Reported button should be handled: held true",
  function()
    local attr_report_data = {
      { PRESENT_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0000 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device_e1.id,
      zigbee_test_utils.build_attribute_report(mock_device_e1, MULTISTATE_INPUT_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device_e1:generate_test_message("main",
    capabilities.button.button.held({state_change = true})))
  end
)

test.register_message_test(
  "Battery voltage report should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device_e1.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device_e1, 30) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_e1:generate_test_message("main", capabilities.battery.battery(100))
    }
  }
)

test.run_registered_tests()
