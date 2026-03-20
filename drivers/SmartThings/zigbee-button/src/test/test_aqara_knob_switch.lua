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
package.path = package.path .. ";./src/?.lua;./src/?/init.lua"
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
local PRIVATE_ATTRIBUTE_ID = 0x0009

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("aqara-knob-switch.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.remote.rkba01",
        server_clusters = { 0x0001 }
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
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.button.supportedButtonValues({ "pushed", "held", "double" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.button.numberOfButtons({ value = 1 })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.button.button.pushed({ state_change = false })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.batteryLevel.battery.normal()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.batteryLevel.type("CR2032")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.batteryLevel.quantity(2)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.knob.rotateAmount({ value = 0, unit = "%" })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.knob.heldRotateAmount({ value = 0, unit = "%" })))
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
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID,
        MFG_CODE,
        data_types.Uint8, 1) })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.knob.supportedAttributes({"rotateAmount", "heldRotateAmount"}, {state_change = true})))
  end
)

test.register_coroutine_test(
  "rotation_monitor_per_handler - normal",
  function()
    local attr_report_data = {
      { 0x0232, data_types.Uint16.ID, 0x0001 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, 
      attr_report_data, MFG_CODE):from_endpoint(0x47)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.knob.rotateAmount({value = 1, unit = "%"}, {state_change = true})))
  end
)

test.register_coroutine_test(
  "rotation_monitor_per_handler - press",
  function()
    local attr_report_data = {
      { 0x0232, data_types.Uint16.ID, 0x0001 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, 
      attr_report_data, MFG_CODE):from_endpoint(0x48)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.knob.heldRotateAmount({value = 1, unit = "%"}, {state_change = true})))
  end
)

test.register_coroutine_test(
  "Reported button should be handled: pushed true",
  function()
    local attr_report_data = {
      { PRESENT_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0001 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, MULTISTATE_INPUT_CLUSTER_ID,
        attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.button.button.pushed({ state_change = true })))
  end
)

test.register_coroutine_test(
  "Reported button should be handled: double true",
  function()
    local attr_report_data = {
      { PRESENT_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0002 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, MULTISTATE_INPUT_CLUSTER_ID,
        attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.button.button.double({ state_change = true })))
  end
)

test.register_coroutine_test(
  "Reported button should be handled: held true",
  function()
    local attr_report_data = {
      { PRESENT_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0000 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, MULTISTATE_INPUT_CLUSTER_ID,
        attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.button.button.held({ state_change = true })))
  end
)

test.register_message_test(
  "Battery Level - Normal",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 30) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.batteryLevel.battery("normal"))
    }
  }
)
test.register_message_test(
  "Battery Level - Warning",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 27) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.batteryLevel.battery("warning"))
    }
  }
)
test.register_message_test(
  "Battery Level - Critical",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 20) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.batteryLevel.battery("critical"))
    }
  }
)

test.run_registered_tests()
