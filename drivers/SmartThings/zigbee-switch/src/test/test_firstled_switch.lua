-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local frameCtrl = require "st.zigbee.zcl.frame_ctrl"

local OnOff = clusters.OnOff
local Scenes = clusters.Scenes
local PRIVATE_CLUSTER_ID = 0xFCCA
local MFG_CODE = 0x1235

local parent_switch_profile_def = t_utils.get_profile_definition("switch-button-light-restore-wireless.yml")
local child_switch_profile_def = t_utils.get_profile_definition("switch-button-wireless.yml")
local scene_switch_profile_def = t_utils.get_profile_definition("button.yml")

local mock_base_device = test.mock_device.build_test_zigbee_device(
  {
    profile = parent_switch_profile_def,
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "FIRSTLED",
        model = "M4S4BAC",
        server_clusters = { 0x0004,0x0006 }
      }
    }
  }
)

local mock_parent_device = test.mock_device.build_test_zigbee_device(
  {
    profile = parent_switch_profile_def,
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "FIRSTLED",
        model = "M4S4BAC",
        server_clusters = { 0x0004,0x0006 }
      }
    }
  }
)

-- Switch 2 (Common Switch)
local mock_first_child = test.mock_device.build_test_child_device(
  {
    profile = child_switch_profile_def,
    device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 2),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%02X", 2)
  }
)

-- Switch 3 (Common Switch)
local mock_second_child = test.mock_device.build_test_child_device(
  {
    profile = child_switch_profile_def,
    device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 3),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%02X", 3)
  }
)

-- Switch 4 (Common Switch)
local mock_third_child = test.mock_device.build_test_child_device(
  {
    profile = child_switch_profile_def,
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
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_parent_device.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    },
    {
       min_api_version = 19
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
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_first_child.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    },
    {
       min_api_version = 19
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
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_second_child.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    },
    {
       min_api_version = 19
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
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_third_child.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    },
    {
       min_api_version = 19
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
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_parent_device.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    },
    {
       min_api_version = 19
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
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_first_child.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    },
    {
       min_api_version = 19
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
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_second_child.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    },
    {
       min_api_version = 19
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
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_third_child.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    },
    {
       min_api_version = 19
    }
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
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_parent_device.id, capability_id = "switch", capability_cmd_id = "on" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device):to_endpoint(0x01) }
      }
    },
    {
       min_api_version = 19
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
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_first_child.id, capability_id = "switch", capability_cmd_id = "on" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device):to_endpoint(0x02) }
      }
    },
    {
       min_api_version = 19
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
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_second_child.id, capability_id = "switch", capability_cmd_id = "on" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device):to_endpoint(0x03) }
      }
    },
    {
       min_api_version = 19
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
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_third_child.id, capability_id = "switch", capability_cmd_id = "on" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device):to_endpoint(0x04) }
      }
    },
    {
       min_api_version = 19
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
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_parent_device.id, capability_id = "switch", capability_cmd_id = "off" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device):to_endpoint(0x01) }
      }
    },
    {
       min_api_version = 19
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
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_first_child.id, capability_id = "switch", capability_cmd_id = "off" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device):to_endpoint(0x02) }
      }
    },
    {
       min_api_version = 19
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
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_second_child.id, capability_id = "switch", capability_cmd_id = "off" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device):to_endpoint(0x03) }
      }
    },
    {
       min_api_version = 19
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
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_third_child.id, capability_id = "switch", capability_cmd_id = "off" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device):to_endpoint(0x04) }
      }
    },
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "RecallScene command should be handled on ep 1",
    function()
      local scenes_command = Scenes.server.commands.RecallScene.build_test_rx(mock_parent_device, 0xF0F0, 0x01)
      local frm_ctrl = frameCtrl(0x11)
      scenes_command.body.zcl_header.frame_ctrl = frm_ctrl
      test.socket.zigbee:__queue_receive({ mock_parent_device.id, scenes_command })
      test.socket.capability:__expect_send(mock_parent_device:generate_test_message("main", capabilities.button.button.pushed(
                                            { state_change = true }
                                            )))
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "RecallScene command should be handled on ep 2",
    function()
      local scenes_command = Scenes.server.commands.RecallScene.build_test_rx(mock_first_child, 0xF0F0, 0x02)
      local frm_ctrl = frameCtrl(0x11)
      scenes_command.body.zcl_header.frame_ctrl = frm_ctrl
      test.socket.zigbee:__queue_receive({ mock_parent_device.id, scenes_command })
      test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.button.button.pushed(
                                            { state_change = true }
                                            )))
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "RecallScene command should be handled on ep 3",
    function()
      local scenes_command = Scenes.server.commands.RecallScene.build_test_rx(mock_second_child, 0xF0F0, 0x03)
      local frm_ctrl = frameCtrl(0x11)
      scenes_command.body.zcl_header.frame_ctrl = frm_ctrl
      test.socket.zigbee:__queue_receive({ mock_parent_device.id, scenes_command })
      test.socket.capability:__expect_send(mock_second_child:generate_test_message("main", capabilities.button.button.pushed(
                                            { state_change = true }
                                            )))
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "RecallScene command should be handled on ep 4",
    function()
      local scenes_command = Scenes.server.commands.RecallScene.build_test_rx(mock_third_child, 0xF0F0, 0x04)
      local frm_ctrl = frameCtrl(0x11)
      scenes_command.body.zcl_header.frame_ctrl = frm_ctrl
      test.socket.zigbee:__queue_receive({ mock_parent_device.id, scenes_command })
      test.socket.capability:__expect_send(mock_third_child:generate_test_message("main", capabilities.button.button.pushed(
                                            { state_change = true }
                                            )))
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "RecallScene command should be handled on ep 5",
    function()
      local scenes_command = Scenes.server.commands.RecallScene.build_test_rx(mock_fourth_child, 0xF0F0, 0x05)
      local frm_ctrl = frameCtrl(0x11)
      scenes_command.body.zcl_header.frame_ctrl = frm_ctrl
      test.socket.zigbee:__queue_receive({ mock_parent_device.id, scenes_command })
      test.socket.capability:__expect_send(mock_fourth_child:generate_test_message("main", capabilities.button.button.pushed(
                                            { state_change = true }
                                            )))
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "RecallScene command should be handled on ep 6",
    function()
      local scenes_command = Scenes.server.commands.RecallScene.build_test_rx(mock_fifth_child, 0xF0F0, 0x06)
      local frm_ctrl = frameCtrl(0x11)
      scenes_command.body.zcl_header.frame_ctrl = frm_ctrl
      test.socket.zigbee:__queue_receive({ mock_parent_device.id, scenes_command })
      test.socket.capability:__expect_send(mock_fifth_child:generate_test_message("main", capabilities.button.button.pushed(
                                            { state_change = true }
                                            )))
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "RecallScene command should be handled on ep 7",
    function()
      local scenes_command = Scenes.server.commands.RecallScene.build_test_rx(mock_sixth_child, 0xF0F0, 0x07)
      local frm_ctrl = frameCtrl(0x11)
      scenes_command.body.zcl_header.frame_ctrl = frm_ctrl
      test.socket.zigbee:__queue_receive({ mock_parent_device.id, scenes_command })
      test.socket.capability:__expect_send(mock_sixth_child:generate_test_message("main", capabilities.button.button.pushed(
                                            { state_change = true }
                                            )))
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "RecallScene command should be handled on ep 8",
    function()
      local scenes_command = Scenes.server.commands.RecallScene.build_test_rx(mock_seventh_child, 0xF0F0, 0x08)
      local frm_ctrl = frameCtrl(0x11)
      scenes_command.body.zcl_header.frame_ctrl = frm_ctrl
      test.socket.zigbee:__queue_receive({ mock_parent_device.id, scenes_command })
      test.socket.capability:__expect_send(mock_seventh_child:generate_test_message("main", capabilities.button.button.pushed(
                                            { state_change = true }
                                            )))
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
  "Handle backlight 0 in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_parent_device:generate_info_changed({
      preferences = { backlight = "0" }
    }))
    test.socket.zigbee:__expect_send({ mock_parent_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_parent_device, PRIVATE_CLUSTER_ID,
        0x0000, MFG_CODE, data_types.Uint8, 0) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle backlight 1 in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_parent_device:generate_info_changed({
      preferences = { backlight = "1" }
    }))
    test.socket.zigbee:__expect_send({ mock_parent_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_parent_device, PRIVATE_CLUSTER_ID,
        0x0000, MFG_CODE, data_types.Uint8, 1) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle backlight 2 in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_parent_device:generate_info_changed({
      preferences = { backlight = "2" }
    }))
    test.socket.zigbee:__expect_send({ mock_parent_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_parent_device, PRIVATE_CLUSTER_ID,
        0x0000, MFG_CODE, data_types.Uint8, 2) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle powerOnStatus 0 in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_parent_device:generate_info_changed({
      preferences = { powerOnStatus = "0" }
    }))
    test.socket.zigbee:__expect_send({ mock_parent_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_parent_device, PRIVATE_CLUSTER_ID,
        0x0001, MFG_CODE, data_types.Uint8, 0) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle powerOnStatus 1 in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_parent_device:generate_info_changed({
      preferences = { powerOnStatus = "1" }
    }))
    test.socket.zigbee:__expect_send({ mock_parent_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_parent_device, PRIVATE_CLUSTER_ID,
        0x0001, MFG_CODE, data_types.Uint8, 1) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle powerOnStatus 2 in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_parent_device:generate_info_changed({
      preferences = { powerOnStatus = "2" }
    }))
    test.socket.zigbee:__expect_send({ mock_parent_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_parent_device, PRIVATE_CLUSTER_ID,
        0x0001, MFG_CODE, data_types.Uint8, 2) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle changeToWirelessSwitch true in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_parent_device:generate_info_changed({
      preferences = { ["stse.changeToWirelessSwitch"] = true }
    }))
    test.socket.zigbee:__expect_send({ mock_parent_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_parent_device, PRIVATE_CLUSTER_ID,
        0x0002, MFG_CODE, data_types.Boolean, true) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle changeToWirelessSwitch false in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_parent_device:generate_info_changed({
      preferences = { ["stse.changeToWirelessSwitch"] = false }
    }))
    test.socket.zigbee:__expect_send({ mock_parent_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_parent_device, PRIVATE_CLUSTER_ID,
        0x0002, MFG_CODE, data_types.Boolean, false) })
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
