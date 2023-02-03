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
local base64 = require "st.base64"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local mgmt_bind_response = require "st.zigbee.zdo.mgmt_bind_response"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration
local WindowCovering = clusters.WindowCovering
local Groups = clusters.Groups

local button_attr = capabilities.button.button
local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("two-buttons-battery.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "IKEA of Sweden",
          model = "TRADFRI open/close remote",
          server_clusters = {0x0019,0x0001}
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
    "Test cases for Button Push(up, down)",
    function()

      test.socket.zigbee:__queue_receive({ mock_device.id, WindowCovering.server.commands.UpOrOpen.build_test_rx(mock_device) })
      test.socket.capability:__expect_send(
          mock_device:generate_test_message("button1", (button_attr.pushed({ state_change = true })))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", (button_attr.pushed({ state_change = true })))
      )
      test.socket.zigbee:__queue_receive({ mock_device.id, WindowCovering.server.commands.DownOrClose.build_test_rx(mock_device) })
      test.socket.capability:__expect_send(
          mock_device:generate_test_message("button2", (button_attr.pushed({ state_change = true })))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", (button_attr.pushed({ state_change = true })))
      )
    end
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes",
    function()
      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device,
                                                                                         30,
                                                                                         21600,
                                                                                         1)
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            zigbee_test_utils.build_bind_request(mock_device,
                                                 zigbee_test_utils.mock_hub_eui,
                                                 PowerConfiguration.ID)
          }
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          zigbee_test_utils.build_bind_request(mock_device,
                                               zigbee_test_utils.mock_hub_eui,
                                               OnOff.ID)
        }
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          zigbee_test_utils.build_mgmt_bind_request(mock_device,
                                                    zigbee_test_utils.mock_hub_eui)
        }
      )
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "ZDO Message handler and adding hub to group",
    function()
      local binding_table = mgmt_bind_response.BindingTableListRecord("\x6A\x9D\xC0\xFE\xFF\x5E\xCF\xD0", 0x01, 0x0006, 0x01, 0xB9F2)
      local response = mgmt_bind_response.MgmtBindResponse({
        status = 0x00,
        total_binding_table_entry_count = 0x01,
        start_index = 0x00,
        binding_table_list_count = 0x01,
        binding_table_entries = { binding_table }
      })
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          zigbee_test_utils.build_zdo_mgmt_bind_response(mock_device, response)
        }
      )
      test.socket.zigbee:__expect_add_hub_to_group(0xB9F2)
    end
)

test.register_coroutine_test(
    "ZDO Message handler and adding hub to group when addr_mode is LONG",
    function()
      local binding_table = mgmt_bind_response.BindingTableListRecord("\x00\x0D\x6F\xFF\xFE\x2F\x19\x73", 0x01, 0x0006, 0x03, "\x28\x6D\x97\x00\x02\x00\x8A\x76", 0x01)
      local response = mgmt_bind_response.MgmtBindResponse({
        status = 0x00,
        total_binding_table_entry_count = 0x01,
        start_index = 0x00,
        binding_table_list_count = 0x01,
        binding_table_entries = { binding_table }
      })
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          zigbee_test_utils.build_zdo_mgmt_bind_response(mock_device, response)
        }
      )
      test.socket.zigbee:__expect_add_hub_to_group(0x0000)
      test.socket.zigbee:__expect_send({mock_device.id, Groups.commands.AddGroup(mock_device, 0x0000) })
    end
)

test.register_coroutine_test(
  "added lifecycle event",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send({
      mock_device.id,
      {
        capability_id = "button", component_id = "main",
        attribute_id = "supportedButtonValues", state = { value = { "pushed" } }
      }
    })
    test.socket.capability:__expect_send({
      mock_device.id,
      {
        capability_id = "button", component_id = "main",
        attribute_id = "numberOfButtons", state = { value = 2 }
      }
    })
    for button_name, _ in pairs(mock_device.profile.components) do
      if button_name ~= "main" then
        test.socket.capability:__expect_send({
          mock_device.id,
          {
            capability_id = "button", component_id = button_name,
            attribute_id = "supportedButtonValues", state = { value = { "pushed" } }
          }
        })
        test.socket.capability:__expect_send({
          mock_device.id,
          {
            capability_id = "button", component_id = button_name,
            attribute_id = "numberOfButtons", state = { value = 1 }
          }
        })
      end
    end
    -- test.socket.capability:__expect_send({
    --   mock_device.id,
    --   {
    --     capability_id = "button", component_id = "main",
    --     attribute_id = "button", state = { value = "pushed" }
    --   }
    -- })

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
    })
    test.wait_for_events()
    end
)

test.run_registered_tests()
