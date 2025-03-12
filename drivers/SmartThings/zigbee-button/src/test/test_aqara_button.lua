-- Copyright 2025 SmartThings
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

local MFG_CODE = 0x115F
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MULTISTATE_INPUT_ATTRIBUTE_ID = 0x0125
local MULTISTATE_INPUT_CLUSTER_ID = 0x0012
local PRESENT_ATTRIBUTE_ID = 0x55

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

local mock_device_h1 = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("two-buttons-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.remote.b28ac1",
        server_clusters = { 0x0001, 0x0012 }
      },
      [2] = {
        id = 2,
        server_clusters = { 0x0001, 0x0012 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device_e1)
  test.mock_device.add_test_device(mock_device_t1)
  test.mock_device.add_test_device(mock_device_h1)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle added lifecycle -- Single Rocker Switch (E1,T1,H1)",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_e1.id, "added" })
    test.socket.capability:__expect_send(mock_device_e1:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed","held","double"})))
    test.socket.capability:__expect_send(mock_device_e1:generate_test_message("main", capabilities.button.numberOfButtons({value = 1})))
    test.socket.capability:__expect_send(mock_device_e1:generate_test_message("main", capabilities.button.button.pushed({state_change = false})))
    test.socket.capability:__expect_send(mock_device_e1:generate_test_message("main", capabilities.battery.battery(100)))
  end
)

test.register_coroutine_test(
  "Handle added lifecycle -- Double Rocker Switch (H1)",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_h1.id, "added" })

    for button_name, component in pairs(mock_device_h1.profile.components) do
      local number_of_buttons = component.id == "main" and 2 or 1
        test.socket.capability:__expect_send(
          mock_device_h1:generate_test_message(
            button_name,
            capabilities.button.supportedButtonValues({ "pushed", "held", "double" })
          )
        )
        test.socket.capability:__expect_send(
          mock_device_h1:generate_test_message(
            button_name,
            capabilities.button.numberOfButtons({ value = number_of_buttons })
          )
        )
    end
    test.socket.capability:__expect_send(mock_device_h1:generate_test_message("main", capabilities.button.button.pushed({state_change = false})))
    test.socket.capability:__expect_send(mock_device_h1:generate_test_message("main", capabilities.battery.battery(100)))
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
     cluster_base.write_manufacturer_specific_attribute(mock_device_e1, PRIVATE_CLUSTER_ID, MULTISTATE_INPUT_ATTRIBUTE_ID, MFG_CODE,
     data_types.Uint8, 2) })
     mock_device_e1:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Handle doConfigure lifecycle -- t1 h1",
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
     cluster_base.write_manufacturer_specific_attribute(mock_device_t1, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE,
     data_types.Uint8, 1) })
    test.socket.zigbee:__expect_send({ mock_device_t1.id,
     cluster_base.write_manufacturer_specific_attribute(mock_device_t1, PRIVATE_CLUSTER_ID, MULTISTATE_INPUT_ATTRIBUTE_ID, MFG_CODE,
     data_types.Uint8, 2) })
     mock_device_t1:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Single Rocker Switch (E1,T1,H1) Reported button should be handled: (pushed double held) true",
  function()
    local attr_report_data_pushed = {
      { PRESENT_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0001 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device_e1.id,
      zigbee_test_utils.build_attribute_report(mock_device_e1, MULTISTATE_INPUT_CLUSTER_ID, attr_report_data_pushed, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device_e1:generate_test_message("main",capabilities.button.button.pushed({state_change = true})))
    test.wait_for_events()
    local attr_report_data_double = {
      { PRESENT_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0002 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device_e1.id,
      zigbee_test_utils.build_attribute_report(mock_device_e1, MULTISTATE_INPUT_CLUSTER_ID, attr_report_data_double, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device_e1:generate_test_message("main",capabilities.button.button.double({state_change = true})))
    test.wait_for_events()
    local attr_report_data_held = {
      { PRESENT_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0000 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device_e1.id,
      zigbee_test_utils.build_attribute_report(mock_device_e1, MULTISTATE_INPUT_CLUSTER_ID, attr_report_data_held, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device_e1:generate_test_message("main",capabilities.button.button.held({state_change = true})))
  end
)

test.register_coroutine_test(
  "Double Rocker Switch (H1) Reported button should be handled: (pushed double held) true",
  function()
    local attr_report_data_pushed = {
      { PRESENT_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0001 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device_h1.id,
      zigbee_test_utils.build_attribute_report(mock_device_h1, MULTISTATE_INPUT_CLUSTER_ID, attr_report_data_pushed, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device_h1:generate_test_message("main",capabilities.button.button.pushed({state_change = true})))
    test.socket.capability:__expect_send(mock_device_h1:generate_test_message("button1", capabilities.button.button.pushed({state_change = true})))
    test.wait_for_events()
    local attr_report_data_double = {
      { PRESENT_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0002 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device_h1.id,
      zigbee_test_utils.build_attribute_report(mock_device_h1, MULTISTATE_INPUT_CLUSTER_ID, attr_report_data_double, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device_h1:generate_test_message("main",capabilities.button.button.double({state_change = true})))
    test.socket.capability:__expect_send(mock_device_h1:generate_test_message("button1", capabilities.button.button.double({state_change = true})))
    test.wait_for_events()
    local attr_report_data_held = {
      { PRESENT_ATTRIBUTE_ID, data_types.Uint16.ID, 0x0000 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device_h1.id,
      zigbee_test_utils.build_attribute_report(mock_device_h1, MULTISTATE_INPUT_CLUSTER_ID, attr_report_data_held, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device_h1:generate_test_message("main",capabilities.button.button.held({state_change = true})))
    test.socket.capability:__expect_send(mock_device_h1:generate_test_message("button1", capabilities.button.button.held({state_change = true})))
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
