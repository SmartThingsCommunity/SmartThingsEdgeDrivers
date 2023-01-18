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
local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration
local Groups = clusters.Groups
local mgmt_bind_response = require "st.zigbee.zdo.mgmt_bind_response"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local FrameCtrl = require "st.zigbee.zcl.frame_ctrl"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("motion-battery.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "IKEA of Sweden",
          model = "TRADFRI motion sensor",
          server_clusters = {0x0001, 0x0006}
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

test.register_message_test(
  "Get initial battery value in added",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {mock_device.id, "added"}
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
      }
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    -- }
  }
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
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device,
                                                                                    30,
                                                                                    21600,
                                                                                    1)
    })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        zigbee_test_utils.build_mgmt_bind_request(mock_device)
      }
    )
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "OnWithTimedOff should be handled active and back to inactive after on time",
  function()
    local on_with_timed_off_command = OnOff.server.commands.OnWithTimedOff.build_test_rx(mock_device, 0x00, 0x0708, 0x0000)
    local frm_ctrl = FrameCtrl(0x01)
    on_with_timed_off_command.body.zcl_header.frame_ctrl = frm_ctrl
    test.timer.__create_and_queue_test_time_advance_timer(0x0708/10, "oneshot")
    test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          on_with_timed_off_command,
        }
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.active()))
    test.wait_for_events()
    test.mock_time.advance_time(180)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive()))
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
  "ZDO Message handler and adding hub to group",
  function()
    local response = mgmt_bind_response.MgmtBindResponse({
      status = 0x00,
      total_binding_table_entry_count = 0x00,
      start_index = 0x00,
      binding_table_list_count = 0x00,
      binding_table_entries = {  }
    })
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        zigbee_test_utils.build_zdo_mgmt_bind_response(mock_device, response)
      }
    )
    test.socket.zigbee:__expect_add_hub_to_group(0x0000)
    test.socket.zigbee:__expect_send({mock_device.id,
      Groups.commands.AddGroup(mock_device, 0x0000)
    })
  end
)

test.run_registered_tests()
