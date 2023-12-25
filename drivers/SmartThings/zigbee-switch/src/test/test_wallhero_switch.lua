-- Copyright 2023 SmartThings
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
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local frameCtrl = require "st.zigbee.zcl.frame_ctrl"
local test = require "integration_test"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff
local Scenes = clusters.Scenes

local common_switch_profile_def = t_utils.get_profile_definition("basic-switch.yml")
local scene_switch_profile_def = t_utils.get_profile_definition("button.yml")

local mock_base_device = test.mock_device.build_test_zigbee_device(
    {
      label = "八位智能开关/场景面板 1",
      profile = common_switch_profile_def,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "WALL HERO",
          model = "ACL-401S8I",
          server_clusters = { 0003,0004,0005,0006 }
        }
      },
      fingerprinted_endpoint_id = 0x01
    }
)

local mock_parent_device = test.mock_device.build_test_zigbee_device(
  {
    profile = common_switch_profile_def,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "WALL HERO",
        model = "ACL-401S8I",
        server_clusters = { 0003,0004,0005,0006 }
      }
    },
    fingerprinted_endpoint_id = 0x01
  }
)

-- Switch 2 (Common Switch)
local mock_first_child = test.mock_device.build_test_child_device(
  {
    profile = common_switch_profile_def,
    device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 2),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%02X", 2)
  }
)

-- Switch 3 (Common Switch)
local mock_second_child = test.mock_device.build_test_child_device(
  {
    profile = common_switch_profile_def,
    device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 3),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%02X", 3)
  }
)

-- Switch 4 (Common Switch)
local mock_third_child = test.mock_device.build_test_child_device(
  {
    profile = common_switch_profile_def,
    device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 4),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%02X", 4)
  }
)

-- Switch 5 (Scene Control Button)
local mock_fourth_child = test.mock_device.build_test_child_device(
  {
    profile = scene_switch_profile_def,
    device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 5),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%02X", 5)
  }
)

-- Switch 6 (Scene Control Button)
local mock_fifth_child = test.mock_device.build_test_child_device(
  {
    profile = scene_switch_profile_def,
    device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 6),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%02X", 6)
  }
)

-- Switch 7 (Scene Control Button)
local mock_sixth_child = test.mock_device.build_test_child_device(
  {
    profile = scene_switch_profile_def,
    device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 7),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%02X", 7)
  }
)

-- Switch 8 (Scene Control Button)
local mock_seventh_child = test.mock_device.build_test_child_device(
  {
    profile = scene_switch_profile_def,
    device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 8),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%02X", 8)
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_base_device)
  test.mock_device.add_test_device(mock_parent_device)
  test.mock_device.add_test_device(mock_first_child)
  test.mock_device.add_test_device(mock_second_child)
  test.mock_device.add_test_device(mock_third_child)
  test.mock_device.add_test_device(mock_fourth_child)
  test.mock_device.add_test_device(mock_fifth_child)
  test.mock_device.add_test_device(mock_sixth_child)
  test.mock_device.add_test_device(mock_seventh_child)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

-- 4 Common Switch Tests
test.register_message_test(
    "Reported on off status should be handled by parent device: on",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_parent_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            true)                               :from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled by first child device: on",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_first_child.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            true)                             :from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_first_child:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled by Second child device: on",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_second_child.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            true)                              :from_endpoint(0x03) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_second_child:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled by third child device: on",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_third_child.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            true)                              :from_endpoint(0x04) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_third_child:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "reported on off status should be handled by parent device: off",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_parent_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            false)                               :from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled by first child device: off",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_first_child.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
        false)                             :from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_first_child:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled by Second child device: off",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_second_child.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
        false)                              :from_endpoint(0x03) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_second_child:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled by third child device: off",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_third_child.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
        false)                              :from_endpoint(0x04) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_third_child:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_coroutine_test(
  "Handle turnOffIndicatorLight in infochanged : On",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_parent_device:generate_info_changed({
      preferences = { ["stse.turnOffIndicatorLight"] = false }
    }))
    test.socket.zigbee:__expect_send({ mock_parent_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_parent_device, 0x0006,
        0x6000, 0x1235, data_types.Uint8, 0x01) })
  end
)

test.register_coroutine_test(
  "Handle turnOffIndicatorLight in infochanged : Off",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_parent_device:generate_info_changed({
      preferences = { ["stse.turnOffIndicatorLight"] = true }
    }))
    test.socket.zigbee:__expect_send({ mock_parent_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_parent_device, 0x0006,
        0x6000, 0x1235, data_types.Uint8, 0x00) })
  end
)

test.register_message_test(
    "Capability on command switch on should be handled : parent device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "capability",
        direction = "receive",
        message = { mock_parent_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device):to_endpoint(0x01) }
      }
    }
)

test.register_message_test(
    "Capability on command switch on should be handled : first child device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_first_child.id, { capability = "switch", component = "main", command = "on", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device):to_endpoint(0x02) }
      }
    }
)

test.register_message_test(
    "Capability on command switch on should be handled : second child device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_second_child.id, { capability = "switch", component = "main", command = "on", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device):to_endpoint(0x03) }
      }
    }
)

test.register_message_test(
    "Capability on command switch on should be handled : third child device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_third_child.id, { capability = "switch", component = "main", command = "on", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device):to_endpoint(0x04) }
      }
    }
)


test.register_message_test(
    "Capability off command switch off should be handled : parent device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_parent_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device):to_endpoint(0x01) }
      }
    }
)

test.register_message_test(
    "Capability off command switch off should be handled : first child device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_first_child.id, { capability = "switch", component = "main", command = "off", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device):to_endpoint(0x02) }
      }
    }
)

test.register_message_test(
    "Capability off command switch off should be handled : second child device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_second_child.id, { capability = "switch", component = "main", command = "off", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device):to_endpoint(0x03) }
      }
    }
)

test.register_message_test(
    "Capability off command switch off should be handled : third child device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_third_child.id, { capability = "switch", component = "main", command = "off", args = { } } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device):to_endpoint(0x04) }
      }
    }
)

-- 4 Scene Control Switch (Actually the key)
test.register_coroutine_test(
    "RecallScene command should be handled",
    function()
      local scenes_command = Scenes.server.commands.RecallScene.build_test_rx(mock_fourth_child, 0xF0F0, 0x05)
      local frm_ctrl = frameCtrl(0x11)
      scenes_command.body.zcl_header.frame_ctrl = frm_ctrl
      test.socket.zigbee:__queue_receive({ mock_parent_device.id, scenes_command })
      test.socket.capability:__expect_send(mock_fourth_child:generate_test_message("main", capabilities.button.button.pushed(
                                            { state_change = true }
                                            )))
    end
)

test.register_coroutine_test(
    "RecallScene command should be handled",
    function()
      local scenes_command = Scenes.server.commands.RecallScene.build_test_rx(mock_fifth_child, 0xF0F0, 0x06)
      local frm_ctrl = frameCtrl(0x11)
      scenes_command.body.zcl_header.frame_ctrl = frm_ctrl
      test.socket.zigbee:__queue_receive({ mock_parent_device.id, scenes_command })
      test.socket.capability:__expect_send(mock_fifth_child:generate_test_message("main", capabilities.button.button.pushed(
                                            { state_change = true }
                                            )))
    end
)

test.register_coroutine_test(
    "RecallScene command should be handled",
    function()
      local scenes_command = Scenes.server.commands.RecallScene.build_test_rx(mock_sixth_child, 0xF0F0, 0x07)
      local frm_ctrl = frameCtrl(0x11)
      scenes_command.body.zcl_header.frame_ctrl = frm_ctrl
      test.socket.zigbee:__queue_receive({ mock_parent_device.id, scenes_command })
      test.socket.capability:__expect_send(mock_sixth_child:generate_test_message("main", capabilities.button.button.pushed(
                                            { state_change = true }
                                            )))
    end
)

test.register_coroutine_test(
    "RecallScene command should be handled",
    function()
      local scenes_command = Scenes.server.commands.RecallScene.build_test_rx(mock_seventh_child, 0xF0F0, 0x08)
      local frm_ctrl = frameCtrl(0x11)
      scenes_command.body.zcl_header.frame_ctrl = frm_ctrl
      test.socket.zigbee:__queue_receive({ mock_parent_device.id, scenes_command })
      test.socket.capability:__expect_send(mock_seventh_child:generate_test_message("main", capabilities.button.button.pushed(
                                            { state_change = true }
                                            )))
    end
)

test.register_coroutine_test(
    "added lifecycle event should create children in parent device",
    function()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_base_device.id, "added" })
      mock_base_device:expect_device_create({
        type = "EDGE_CHILD",
        label = "八位智能开关/场景面板 2",
        profile = "basic-switch",
        parent_device_id = mock_base_device.id,
        parent_assigned_child_key = "02"
      })
      mock_base_device:expect_device_create({
        type = "EDGE_CHILD",
        label = "八位智能开关/场景面板 3",
        profile = "basic-switch",
        parent_device_id = mock_base_device.id,
        parent_assigned_child_key = "03"
      })
      mock_base_device:expect_device_create({
        type = "EDGE_CHILD",
        label = "八位智能开关/场景面板 4",
        profile = "basic-switch",
        parent_device_id = mock_base_device.id,
        parent_assigned_child_key = "04"
      })
      mock_base_device:expect_device_create({
        type = "EDGE_CHILD",
        label = "八位智能开关/场景面板 5",
        profile = "button",
        parent_device_id = mock_base_device.id,
        parent_assigned_child_key = "05"
      })
      mock_base_device:expect_device_create({
        type = "EDGE_CHILD",
        label = "八位智能开关/场景面板 6",
        profile = "button",
        parent_device_id = mock_base_device.id,
        parent_assigned_child_key = "06"
      })
      mock_base_device:expect_device_create({
        type = "EDGE_CHILD",
        label = "八位智能开关/场景面板 7",
        profile = "button",
        parent_device_id = mock_base_device.id,
        parent_assigned_child_key = "07"
      })
      mock_base_device:expect_device_create({
        type = "EDGE_CHILD",
        label = "八位智能开关/场景面板 8",
        profile = "button",
        parent_device_id = mock_base_device.id,
        parent_assigned_child_key = "08"
      })
      test.socket.zigbee:__expect_send({
        mock_base_device.id,
        OnOff.attributes.OnOff:read(mock_base_device):to_endpoint(0x01)
      })
    end
)

test.run_registered_tests()
