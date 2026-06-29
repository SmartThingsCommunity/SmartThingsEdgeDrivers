-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local frameCtrl = require "st.zigbee.zcl.frame_ctrl"
local device_lib = require "st.device"

local OnOff = clusters.OnOff
local Scenes = clusters.Scenes

local PRIVATE_CLUSTER_ID = 0xFCCA
local MFG_CODE = 0x1235
local FINGERPRINTS = require("firstled-io.fingerprints")

local parent_profile = t_utils.get_profile_definition("switch-button-light-restore-wireless.yml")
local child_switch_profile = t_utils.get_profile_definition("switch-button-wireless.yml")

local function get_children_amount(device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.children
    end
  end
end

local function get_button_amount(device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.buttons
    end
  end
end

local function get_child_profile_name(device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.child_profile
    end
  end
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end
-- ====================== Mock Devices ======================
local mock_parent = test.mock_device.build_test_zigbee_device({
  profile = parent_profile,
  manufacturer = "FIRSTLED",
  model = "M4S4BAC",
  label = "Mirror Series 4x4 1",
  fingerprinted_endpoint_id = 0x01,
  zigbee_endpoints = {
    [1] = { id = 1, manufacturer = "FIRSTLED", model = "M4S4BAC", server_clusters = { 0x0004, 0x0006 } }
  }
})

local mock_children = {}

for i = 2, 4 do
  local name = string.format("%s%d", string.sub("Mirror Series 4x4 1", 0, -2), i)
  table.insert(mock_children, test.mock_device.build_test_child_device({
    type = "EDGE_CHILD",
    profile = child_switch_profile,
    label = name,
    device_network_id = string.format("%04X:%02X", mock_parent:get_short_address(), i),
    parent_device_id = mock_parent.id,
    parent_assigned_child_key = string.format("%02X", i),
    vendor_provided_label = name
  }))
end

local function test_init()
  test.mock_device.add_test_device(mock_parent)
  for _, child in ipairs(mock_children) do
    test.mock_device.add_test_device(child)
  end
end

test.set_test_init_function(test_init)

-- ====================== can_handle ======================
test.register_coroutine_test("can_handle should return true and handler for matching device", function()
  local can_handle = require("firstled-io.can_handle")
  local result, handler = can_handle({}, nil, mock_parent)
  assert(result == true)
  assert(handler ~= nil)
  end,
  {
    min_api_version = 19
  }
)

test.register_coroutine_test("can_handle should return false for non-matching device", function()
  local can_handle = require("firstled-io.can_handle")
  local non_match = test.mock_device.build_test_zigbee_device({
    manufacturer = "OTHER", model = "OTHER", profile = parent_profile
  })
  local result = can_handle({}, nil, non_match)
  assert(result == false)
  end,
  {
    min_api_version = 19
  }
)

-- ====================== Lifecycle ======================
test.register_coroutine_test("device_init should set find_child for parent", function()
  test.socket.device_lifecycle:__queue_receive({mock_parent.id, "init"})
  end,
  {
    min_api_version = 19
  }
)

-- ====================== device_added ======================
test.register_coroutine_test("device_added - Zigbee Parent should create children and emit capabilities", function()
  test.socket.device_lifecycle:__queue_receive({mock_parent.id, "added"})
  if mock_parent.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    local children_amount = get_children_amount(mock_parent)
    if children_amount >= 2 then
      for i = 2, children_amount, 1 do
        if find_child(mock_parent, i) == nil then
          local name = string.format("%s%d", string.sub(mock_parent.label, 0, -2), i)
          local expected_metadata = {
              type = "EDGE_CHILD",
              label = name,
              profile = get_child_profile_name(mock_parent),
              parent_device_id = mock_parent.id,
              parent_assigned_child_key = string.format("%02X", i),
            }
            mock_parent:expect_device_create(expected_metadata)
          end
        end
    end
    local button_amount = get_button_amount(mock_parent)
    if button_amount >= 1 then
      for i = children_amount + 1, children_amount + button_amount, 1 do
        if find_child(mock_parent, i) == nil then
          local name = string.format("%s%d", string.sub(mock_parent.label, 0, -2), i)
          local expected_metadata = {
            type = "EDGE_CHILD",
            label = name,
            profile = "button",
            parent_device_id = mock_parent.id,
            parent_assigned_child_key = string.format("%02X", i),
          }
          mock_parent:expect_device_create(expected_metadata)
        end
      end
    end

  elseif mock_parent.network_type == "DEVICE_EDGE_CHILD" then
    test.socket.capability:__expect_send(mock_parent:generate_test_message("main",
      capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_parent:generate_test_message("main",
      capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
  end
  end,
  {
    min_api_version = 19
  }
)

local function test_device_added_child(ep, name)
  test.register_coroutine_test(name, function()
    local child = mock_children[ep-1]
    test.socket.device_lifecycle:__queue_receive({child.id, "added"})

    test.socket.capability:__expect_send(child:generate_test_message("main",
      capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })))

    test.socket.capability:__expect_send(child:generate_test_message("main",
      capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
  end,
  {
    min_api_version = 19
  }
)
end

for ep = 2, 4 do
  test_device_added_child(ep, "test_device_added_child  endpoint " .. ep)
end

-- ====================== Preferences ======================
test.register_coroutine_test("infoChanged - backlight 0", function()
  test.socket.device_lifecycle:__queue_receive(mock_parent:generate_info_changed({ preferences = { backlight = "0" }}))
  test.socket.zigbee:__expect_send({ mock_parent.id,
    cluster_base.write_manufacturer_specific_attribute(mock_parent, PRIVATE_CLUSTER_ID, 0x0000, MFG_CODE, data_types.Uint8, 0)
  })
  end,
  {
    min_api_version = 19
  }
)

test.register_coroutine_test("infoChanged - backlight 1", function()
  test.socket.device_lifecycle:__queue_receive(mock_parent:generate_info_changed({ preferences = { backlight = "1" }}))
  test.socket.zigbee:__expect_send({ mock_parent.id,
    cluster_base.write_manufacturer_specific_attribute(mock_parent, PRIVATE_CLUSTER_ID, 0x0000, MFG_CODE, data_types.Uint8, 1)
  })
  end,
  {
    min_api_version = 19
  }
)

test.register_coroutine_test("infoChanged - backlight 2", function()
  test.socket.device_lifecycle:__queue_receive(mock_parent:generate_info_changed({ preferences = { backlight = "2" }}))
  test.socket.zigbee:__expect_send({ mock_parent.id,
    cluster_base.write_manufacturer_specific_attribute(mock_parent, PRIVATE_CLUSTER_ID, 0x0000, MFG_CODE, data_types.Uint8, 2)
  })
  end,
  {
    min_api_version = 19
  }
)

test.register_coroutine_test("infoChanged - powerOnStatus 0", function()
  test.socket.device_lifecycle:__queue_receive(mock_parent:generate_info_changed({ preferences = { powerOnStatus = "0" }}))
  test.socket.zigbee:__expect_send({ mock_parent.id,
    cluster_base.write_manufacturer_specific_attribute(mock_parent, PRIVATE_CLUSTER_ID, 0x0001, MFG_CODE, data_types.Uint8, 0)
  })
  end,
  {
    min_api_version = 19
  }
)

test.register_coroutine_test("infoChanged - powerOnStatus", function()
  test.socket.device_lifecycle:__queue_receive(mock_parent:generate_info_changed({ preferences = { powerOnStatus = "1" }}))
  test.socket.zigbee:__expect_send({ mock_parent.id,
    cluster_base.write_manufacturer_specific_attribute(mock_parent, PRIVATE_CLUSTER_ID, 0x0001, MFG_CODE, data_types.Uint8, 1)
  })
  end,
  {
    min_api_version = 19
  }
)

test.register_coroutine_test("infoChanged - powerOnStatus 2", function()
  test.socket.device_lifecycle:__queue_receive(mock_parent:generate_info_changed({ preferences = { powerOnStatus = "2" }}))
  test.socket.zigbee:__expect_send({ mock_parent.id,
    cluster_base.write_manufacturer_specific_attribute(mock_parent, PRIVATE_CLUSTER_ID, 0x0001, MFG_CODE, data_types.Uint8, 2)
  })
  end,
  {
    min_api_version = 19
  }
)

test.register_coroutine_test("infoChanged - stse.changeToWirelessSwitch true", function()
  test.socket.device_lifecycle:__queue_receive(mock_parent:generate_info_changed({ preferences = { ["stse.changeToWirelessSwitch"] = true }}))
  test.socket.zigbee:__expect_send({ mock_parent.id,
    cluster_base.write_manufacturer_specific_attribute(mock_parent, PRIVATE_CLUSTER_ID, 0x0002, MFG_CODE, data_types.Boolean, true)
  })
  mock_parent:expect_metadata_update({ profile = "switch-button-light-restore-wireless" })
  end,
  {
    min_api_version = 19
  }
)

test.register_coroutine_test("infoChanged - stse.changeToWirelessSwitch false", function()
  test.socket.device_lifecycle:__queue_receive(mock_parent:generate_info_changed({ preferences = { ["stse.changeToWirelessSwitch"] = false }}))
  test.socket.zigbee:__expect_send({ mock_parent.id,
    cluster_base.write_manufacturer_specific_attribute(mock_parent, PRIVATE_CLUSTER_ID, 0x0002, MFG_CODE, data_types.Boolean, false)
  })
  mock_parent:expect_metadata_update({ profile = "switch-light-restore-wireless" })
  end,
  {
    min_api_version = 19
  }
)

local function test_child_changeToWirelessSwitch_true(ep, name)
  test.register_coroutine_test(name, function()
    test.socket.device_lifecycle:__queue_receive(mock_children[ep]:generate_info_changed({ preferences = { ["stse.changeToWirelessSwitch"] = true }}))
    test.socket.zigbee:__expect_send({ mock_parent.id,
      cluster_base.write_manufacturer_specific_attribute(mock_parent, PRIVATE_CLUSTER_ID, 0x0002, MFG_CODE, data_types.Boolean, true):to_endpoint(ep+1)
    })
    mock_children[ep]:expect_metadata_update({ profile = "switch-button-wireless" })
    end,
    {
      min_api_version = 19
    }
  )
end

local function test_child_changeToWirelessSwitch_false(ep, name)
  test.register_coroutine_test(name, function()
    test.socket.device_lifecycle:__queue_receive(mock_children[ep]:generate_info_changed({ preferences = { ["stse.changeToWirelessSwitch"] = false }}))
    test.socket.zigbee:__expect_send({ mock_parent.id,
      cluster_base.write_manufacturer_specific_attribute(mock_parent, PRIVATE_CLUSTER_ID, 0x0002, MFG_CODE, data_types.Boolean, false):to_endpoint(ep+1)
    })
    mock_children[ep]:expect_metadata_update({ profile = "switch-wireless" })
    end,
    {
      min_api_version = 19
    }
  )
end

for ep = 1, 3 do
  test_child_changeToWirelessSwitch_true(ep, "children infoChanged - stse.changeToWirelessSwitch true " .. ep + 1)
end

for ep = 1, 3 do
  test_child_changeToWirelessSwitch_false(ep, "children infoChanged - stse.changeToWirelessSwitch false " .. ep + 1)
end

-- ====================== Commands ======================
test.register_message_test("Parent device - On command", {
  { channel = "device_lifecycle", direction = "receive", message = { mock_parent.id, "init" }},
  { channel = "capability", direction = "receive", message = { mock_parent.id, { capability = "switch", component = "main", command = "on", args = {} }}},
  { channel = "devices", direction = "send", message = { "register_native_capability_cmd_handler", { device_uuid = mock_parent.id, capability_id = "switch", capability_cmd_id = "on" }}},
  { channel = "zigbee", direction = "send", message = { mock_parent.id, OnOff.server.commands.On(mock_parent):to_endpoint(0x01) }}
  },
  {
    min_api_version = 19
  }
)

test.register_message_test("Parent device - Off command", {
  { channel = "capability", direction = "receive", message = { mock_parent.id, { capability = "switch", component = "main", command = "off", args = {} }}},
  { channel = "devices", direction = "send", message = { "register_native_capability_cmd_handler", { device_uuid = mock_parent.id, capability_id = "switch", capability_cmd_id = "off" }}},
  { channel = "zigbee", direction = "send", message = { mock_parent.id, OnOff.server.commands.Off(mock_parent):to_endpoint(0x01) }}
  },
  {
    min_api_version = 19
  }
)

-- ====================== Attribute Reports ======================
test.register_coroutine_test(
  "OnOff report on parent endpoint",
  function()
    test.socket.device_lifecycle:__queue_receive({mock_parent.id, "init"})

    local report = OnOff.attributes.OnOff:build_test_attr_report(mock_parent, true):from_endpoint(0x01)
    test.socket.zigbee:__queue_receive({mock_parent.id, report})

    test.socket.capability:__expect_send(mock_parent:generate_test_message("main", capabilities.switch.switch.on()))
    mock_parent:expect_native_attr_handler_registration("switch", "switch")
  end,
  {
    min_api_version = 19
  }
)

test.register_coroutine_test(
  "OnOff report off parent endpoint",
  function()
    test.socket.device_lifecycle:__queue_receive({mock_parent.id, "init"})

    local report = OnOff.attributes.OnOff:build_test_attr_report(mock_parent, false):from_endpoint(0x01)
    test.socket.zigbee:__queue_receive({mock_parent.id, report})

    test.socket.capability:__expect_send(mock_parent:generate_test_message("main", capabilities.switch.switch.off()))
    mock_parent:expect_native_attr_handler_registration("switch", "switch")
  end,
  {
    min_api_version = 19
  }
)

local function test_on_cmd(ep, name)
  test.register_message_test(name, {
    { channel = "capability", direction = "receive", message = { mock_children[ep].id, { capability = "switch", component = "main", command = "on", args = {} }}},
    { channel = "devices", direction = "send", message = { "register_native_capability_cmd_handler", { device_uuid = mock_children[ep].id, capability_id = "switch", capability_cmd_id = "on" }}},
    { channel = "zigbee", direction = "send", message = { mock_parent.id, OnOff.server.commands.On(mock_parent):to_endpoint(ep+1) }}
  },
  {
    min_api_version = 19
  })
end

local function test_off_cmd(ep, name)
  test.register_message_test(name, {
    { channel = "capability", direction = "receive", message = { mock_children[ep].id, { capability = "switch", component = "main", command = "off", args = {} }}},
    { channel = "devices", direction = "send", message = { "register_native_capability_cmd_handler", { device_uuid = mock_children[ep].id, capability_id = "switch", capability_cmd_id = "off" }}},
    { channel = "zigbee", direction = "send", message = { mock_parent.id, OnOff.server.commands.Off(mock_parent):to_endpoint(ep+1) }}
  },
  {
    min_api_version = 19
  })
end

local function test_onoff_report_on_cmd(ep, name)
  test.register_coroutine_test(
    name,
    function()
      test.socket.device_lifecycle:__queue_receive({mock_parent.id, "init"})

      local report = OnOff.attributes.OnOff:build_test_attr_report(mock_parent, true):from_endpoint(ep+1)
      test.socket.zigbee:__queue_receive({mock_children[ep].id, report})

      test.socket.capability:__expect_send(mock_children[ep]:generate_test_message("main", capabilities.switch.switch.on()))
      mock_children[ep]:expect_native_attr_handler_registration("switch", "switch")
    end,
    {
      min_api_version = 19
    }
  )
end

local function test_onoff_report_off_cmd(ep, name)
  test.register_coroutine_test(
    name,
    function()
      test.socket.device_lifecycle:__queue_receive({mock_parent.id, "init"})

      local report = OnOff.attributes.OnOff:build_test_attr_report(mock_parent, false):from_endpoint(ep+1)
      test.socket.zigbee:__queue_receive({mock_children[ep].id, report})

      test.socket.capability:__expect_send(mock_children[ep]:generate_test_message("main", capabilities.switch.switch.off()))
      mock_children[ep]:expect_native_attr_handler_registration("switch", "switch")
    end,
    {
      min_api_version = 19
    }
  )
end

-- ====================== RecallScene ======================
local function test_recall_scene(ep, name)
  test.register_coroutine_test(name, function()
    local cmd = Scenes.server.commands.RecallScene.build_test_rx(mock_parent, 0xF0F0, ep)
    cmd.body.zcl_header.frame_ctrl = frameCtrl(0x11)
    test.socket.zigbee:__queue_receive({ mock_parent.id, cmd })
    test.socket.capability:__expect_send(mock_parent:generate_test_message("main",
      capabilities.button.button.pushed({ state_change = true })))
  end,
  {
    min_api_version = 19
  })
end

local function test_child_recall_scene(ep, name)
  test.register_coroutine_test(name, function()
    local cmd = Scenes.server.commands.RecallScene.build_test_rx(mock_parent, 0xF0F0, ep + 1)
    cmd.body.zcl_header.frame_ctrl = frameCtrl(0x11)
    test.socket.zigbee:__queue_receive({ mock_children[ep].id, cmd })
    test.socket.capability:__expect_send(mock_children[ep]:generate_test_message("main",
      capabilities.button.button.pushed({ state_change = true })))
  end,
  {
    min_api_version = 19
  })
end

for ep = 1, 1 do
  test_recall_scene(ep, "RecallScene on parent endpoint " .. ep)
end

for ep = 1, 3 do
  test_child_recall_scene(ep, "test_child_recall_scene on endpoint " .. ep + 1)
end

for ep = 1, 3 do
  test_on_cmd(ep, "children test_on_cmd on endpoint " .. ep + 1)
end

for ep = 1, 3 do
  test_off_cmd(ep, "children test_off_cmd on endpoint " .. ep + 1)
end

for ep = 1, 3 do
  test_onoff_report_on_cmd(ep, "children test_onoff_report_on_cmd  endpoint " .. ep + 1)
end

for ep = 1, 3 do
  test_onoff_report_off_cmd(ep, "children test_onoff_report_off_cmd  endpoint " .. ep + 1)
end

test.run_registered_tests()
