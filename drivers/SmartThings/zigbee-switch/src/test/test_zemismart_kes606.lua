-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local version = require "version"
local t_utils = require "integration_test.utils"
local zb_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local utils = require "st.utils"
local json = require "st.json"
local messages = require "st.zigbee.messages"
local constants = require "st.zigbee.constants"
local zcl_messages = require "st.zigbee.zcl"
local default_response = require "st.zigbee.zcl.global_commands.default_response"
local Status = require "st.zigbee.generated.types.ZclStatus"
local OnOff = clusters.OnOff

local PARENT_PROFILE = "scene-switch-4-gang.yml"
local SWITCH_PROFILE = "scene-switch-child.yml"
local SCENE_PROFILE = "scene-switch-child-scene.yml"

local function make_parent(label)
  local endpoints = {}
  for ep = 1, 4 do
    endpoints[ep] = {
      id = ep, manufacturer = "_TZ3000_hurauima", model = "TS0726",
      server_clusters = { 0x0000, 0x0006, 0xE001 },
    }
  end
  return test.mock_device.build_test_zigbee_device({
    profile = t_utils.get_profile_definition(PARENT_PROFILE),
    manufacturer = "_TZ3000_hurauima", model = "TS0726", label = label,
    fingerprinted_endpoint_id = 1, zigbee_endpoints = endpoints,
  })
end

local function make_children(parent, profile)
  local children = {}
  for ep = 1, 4 do
    children[ep] = test.mock_device.build_test_child_device({
      profile = t_utils.get_profile_definition(profile), parent_device_id = parent.id,
      parent_assigned_child_key = string.format("%02X", ep), label = parent.label .. " L" .. ep,
    })
  end
  return children
end

local parent = make_parent("Relay sample")
local children = make_children(parent, SWITCH_PROFILE)
local scene_parent = make_parent("Scene sample")
local scene_children = make_children(scene_parent, SCENE_PROFILE)
zb_utils.prepare_zigbee_env_info()

local function expect_button_metadata(device)
  test.socket.capability:__expect_send(device:generate_test_message("main",
    capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(device:generate_test_message("main",
    capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })))
end

local function initialize_devices()
  test.socket.capability:__set_channel_ordering("relaxed")
  test.mock_device.add_test_device(parent)
  test.mock_device.add_test_device(scene_parent)
  expect_button_metadata(parent)
  expect_button_metadata(scene_parent)
  for ep = 1, 4 do
    test.mock_device.add_test_device(children[ep])
    test.mock_device.add_test_device(scene_children[ep])
    expect_button_metadata(scene_children[ep])
  end
end

test.set_test_init_function(initialize_devices)

local function enum_read(device, attribute, ep, cluster)
  return cluster_base.read_attribute(device, data_types.ClusterId(cluster or 0xE001),
    data_types.AttributeId(attribute)):to_endpoint(ep)
end

local function enum_write(device, attribute, value, ep, cluster)
  return cluster_base.write_attribute(device, data_types.ClusterId(cluster or 0xE001),
    data_types.AttributeId(attribute), data_types.Enum8(value)):to_endpoint(ep)
end

local function expect_parent_switch(device, state)
  test.socket.capability:__expect_send(device:generate_test_message("main", capabilities.switch.switch(state)))
end

local function receive_mode_report(device, ep, mode)
  test.socket.zigbee:__queue_receive({ device.id, zb_utils.build_attribute_report(device,
    0xE001, { { 0xD020, data_types.Enum8.ID, mode == "scene" and 1 or 0 } }):from_endpoint(ep) })
  test.wait_for_events()
end

local function confirm_switch_modes()
  for ep = 1, 4 do
    test.socket.zigbee:__expect_send({ parent.id, OnOff.attributes.OnOff:read(parent):to_endpoint(ep) })
    receive_mode_report(parent, ep, "switch")
  end
end

local function confirm_scene_modes()
  for ep = 1, 4 do
    if ep == 4 then expect_parent_switch(scene_parent, "off") end
    receive_mode_report(scene_parent, ep, "scene")
  end
end

local function receive_relay_report(device, child, ep, on, aggregate)
  if child then
    test.socket.capability:__expect_send(child:generate_test_message("main",
      capabilities.switch.switch(on and "on" or "off")))
  end
  if aggregate then expect_parent_switch(device, aggregate) end
  test.socket.zigbee:__queue_receive({ device.id,
    OnOff.attributes.OnOff:build_test_attr_report(device, on):from_endpoint(ep) })
  test.wait_for_events()
end

local function send_switch_command(device, name)
  test.socket.capability:__queue_receive({ device.id,
    { capability = "switch", component = "main", command = name, args = {} } })
end

local function expect_relay_command(device, ep, on)
  test.socket.zigbee:__expect_send({ device.id,
    (on and OnOff.server.commands.On(device) or OnOff.server.commands.Off(device)):to_endpoint(ep) })
end

local function expect_mode_request(device, ep, mode)
  test.socket.zigbee:__expect_send({ device.id, enum_write(device, 0xD020, mode == "scene" and 1 or 0, ep) })
  test.socket.zigbee:__expect_send({ device.id, enum_read(device, 0xD020, ep) })
end

local function assert_nested_dispatch(dispatcher, device, message)
  local driver = test.driver_wrapper.driver_under_test
  local tuya_name = version.api >= 16 and "tuya-multi" or require("tuya-multi").NAME
  local kes606_name = version.api >= 16 and "zemismart-kes606" or require("zemismart-kes606").NAME
  local tuya_dispatchers = dispatcher:find_child_dispatchers(driver, device, message)
  assert(#tuya_dispatchers == 1 and tuya_dispatchers[1].name == tuya_name)
  local nested = tuya_dispatchers[1]:find_child_dispatchers(driver, device, message)
  assert(#nested == 1 and nested[1].name == kes606_name,
    "KES606 must dispatch exactly once through the nested Tuya handler")
end

test.register_coroutine_test("Only the exact four-gang fingerprint and its children use KES606", function()
  local matches = require "zemismart-kes606.can_handle"
  assert(matches({}, nil, parent))
  for ep = 1, 4 do assert(matches({}, nil, children[ep])) end
  for _, fingerprint in ipairs({
    { manufacturer = "_TZ3000_other", model = "TS0726" },
    { manufacturer = "_TZ3000_hurauima", model = "TS0004" },
  }) do
    fingerprint.profile = t_utils.get_profile_definition(PARENT_PROFILE)
    assert(not matches({}, nil, test.mock_device.build_test_zigbee_device(fingerprint)))
  end
  assert(not matches({}, nil, nil))
end)

test.register_coroutine_test("Parent and children dispatch through the nested Tuya handler", function()
  local driver = test.driver_wrapper.driver_under_test
  for _, devices in ipairs({ { parent, scene_parent }, children, scene_children }) do
    for _, device in ipairs(devices) do
      assert_nested_dispatch(driver.capability_dispatcher, device,
        { capability = "switch", component = "main", command = "on", args = {} })
      assert_nested_dispatch(driver.lifecycle_dispatcher, device, "init")
    end
  end
end)

test.register_coroutine_test("Unknown modes ignore commands and reports without declaring all off", function()
  for _, device in ipairs({ parent, scene_parent, children[1], scene_children[1] }) do
    send_switch_command(device, "on")
  end
  receive_relay_report(parent, nil, 1, true)
  test.socket.zigbee:__queue_receive({ scene_parent.id,
    zb_utils.build_custom_command_id(scene_parent, 0x0006, 0xFD, nil, "", 1) })
end)

for _, key in ipairs({ "00", "05", "01-extra", "gang1", "invalid" }) do
  local malformed = test.mock_device.build_test_child_device({
    profile = t_utils.get_profile_definition(SWITCH_PROFILE), parent_device_id = parent.id,
    parent_assigned_child_key = key, label = "Malformed KES606 child " .. key,
  })
  test.register_coroutine_test("Malformed child key " .. key .. " cannot target a relay", function()
    confirm_switch_modes()
    send_switch_command(malformed, "on")
    send_switch_command(malformed, "off")
    test.socket.device_lifecycle:__queue_receive(malformed:generate_info_changed({
      preferences = { switchMode = "scene", countdownSeconds = 30 }
    }))
  end, { test_init = function()
    initialize_devices()
    test.mock_device.add_test_device(malformed)
  end })
end

test.register_coroutine_test("Added creates four children with standard endpoint keys", function()
  test.socket.device_lifecycle:__queue_receive({ parent.id, "added" })
end, {
  test_init = function()
    test.mock_device.add_test_device(parent)
    expect_button_metadata(parent)
    for ep = 1, 4 do
      parent:expect_device_create({ type = "EDGE_CHILD", parent_device_id = parent.id,
        parent_assigned_child_key = string.format("%02X", ep), label = parent.label .. " L" .. ep,
        profile = "scene-switch-child" })
    end
  end,
})

test.register_coroutine_test("Repeated initialization preserves children and does not synthesize presses", function()
  for _ = 1, 2 do
    expect_button_metadata(parent)
    test.socket.device_lifecycle:__queue_receive({ parent.id, "init" })
    test.wait_for_events()
  end
  for ep = 1, 4 do
    expect_button_metadata(scene_children[ep])
    test.socket.device_lifecycle:__queue_receive({ scene_children[ep].id, "init" })
  end
end)

for ep = 1, 4 do
  for _, on in ipairs({ true, false }) do
    local name = on and "on" or "off"
    test.register_coroutine_test("Relay " .. ep .. " " .. name .. " uses the standard child endpoint", function()
      confirm_switch_modes()
      expect_relay_command(parent, ep, on)
      send_switch_command(children[ep], name)
    end)
    test.register_coroutine_test("Relay report " .. ep .. " " .. name .. " updates its child and aggregate", function()
      confirm_switch_modes()
      receive_relay_report(parent, children[ep], ep, on, on and "on" or nil)
    end)
  end

  test.register_coroutine_test("Scene endpoint " .. ep .. " emits physical presses and ignores relay traffic", function()
    confirm_scene_modes()
    receive_relay_report(scene_parent, nil, ep, true)
    send_switch_command(scene_children[ep], "on")
    for _ = 1, 2 do
      for _, device in ipairs({ scene_children[ep], scene_parent }) do
        test.socket.capability:__expect_send(device:generate_test_message("main",
          capabilities.button.button.pushed({ state_change = true })))
      end
      test.socket.zigbee:__queue_receive({ scene_parent.id,
        zb_utils.build_custom_command_id(scene_parent, 0x0006, 0xFD, nil, "", ep) })
      test.wait_for_events()
    end
  end)

  test.register_coroutine_test("Relay endpoint " .. ep .. " ignores scene commands", function()
    confirm_switch_modes()
    test.socket.zigbee:__queue_receive({ parent.id,
      zb_utils.build_custom_command_id(parent, 0x0006, 0xFD, nil, "", ep) })
  end)

  test.register_coroutine_test("Mode preference " .. ep .. " waits for D020 before changing profile", function()
    confirm_switch_modes()
    expect_mode_request(parent, ep, "scene")
    test.socket.device_lifecycle:__queue_receive(children[ep]:generate_info_changed({
      preferences = { switchMode = "scene" }
    }))
    test.wait_for_events()
    expect_relay_command(parent, ep, true)
    send_switch_command(children[ep], "on")
    test.wait_for_events()
    children[ep]:expect_metadata_update({ profile = "scene-switch-child-scene" })
    receive_mode_report(parent, ep, "scene")
    send_switch_command(children[ep], "on")
  end)

  test.register_coroutine_test("Countdown " .. ep .. " targets its endpoint", function()
    test.socket.zigbee:__expect_send({ parent.id, OnOff.server.commands.OnWithTimedOff(parent,
      data_types.Uint8(0), data_types.Uint16(30), data_types.Uint16(30)):to_endpoint(ep) })
    test.socket.device_lifecycle:__queue_receive(children[ep]:generate_info_changed({
      preferences = { countdownSeconds = 30 }
    }))
  end)
end

test.register_coroutine_test("Invalid D020 values and endpoints cannot change profiles or press buttons", function()
  for _, ep in ipairs({ 1, 5 }) do
    test.socket.zigbee:__queue_receive({ parent.id, zb_utils.build_attribute_report(parent,
      0xE001, { { 0xD020, data_types.Enum8.ID, ep == 1 and 2 or 1 } }):from_endpoint(ep) })
  end
  test.socket.zigbee:__queue_receive({ scene_parent.id,
    zb_utils.build_custom_command_id(scene_parent, 0x0006, 0xFD, nil, "", 5) })
end)

test.register_coroutine_test("Indicator and power-on preferences retain their documented writes", function()
  test.socket.zigbee:__expect_send({ parent.id, enum_write(parent, 0x8001, 2, 1, 0x0006) })
  test.socket.zigbee:__expect_send({ parent.id, enum_write(parent, 0x8002, 0, 1, 0x0006) })
  test.socket.zigbee:__expect_send({ parent.id, enum_write(parent, 0xD010, 1, 3) })
  test.socket.device_lifecycle:__queue_receive(parent:generate_info_changed({
    preferences = { lightMode = "pos", relayStatus = "off", relayStatus3 = "on" }
  }))
end)

for _, on in ipairs({ true, false }) do
  local name = on and "on" or "off"
  test.register_coroutine_test("Parent " .. name .. " controls all confirmed relay endpoints", function()
    confirm_switch_modes()
    for ep = 1, 4 do expect_relay_command(parent, ep, on) end
    send_switch_command(parent, name)
  end)
  test.register_coroutine_test("Parent " .. name .. " excludes confirmed scene endpoints", function()
    confirm_switch_modes()
    for _, ep in ipairs({ 2, 4 }) do
      children[ep]:expect_metadata_update({ profile = "scene-switch-child-scene" })
      receive_mode_report(parent, ep, "scene")
    end
    for _, ep in ipairs({ 1, 3 }) do expect_relay_command(parent, ep, on) end
    send_switch_command(parent, name)
  end)
  test.register_coroutine_test("Parent " .. name .. " is inert with all scene endpoints", function()
    confirm_scene_modes()
    send_switch_command(scene_parent, name)
  end)
end

test.register_coroutine_test("Parent waits for unknown child states before all-off and deduplicates aggregate events", function()
  confirm_switch_modes()
  receive_relay_report(parent, children[3], 3, true, "on")
  receive_relay_report(parent, children[3], 3, false)
  for _, ep in ipairs({ 1, 4, 2 }) do
    receive_relay_report(parent, children[ep], ep, false, ep == 2 and "off" or nil)
  end
  receive_relay_report(parent, children[2], 2, false)
  receive_relay_report(parent, children[1], 1, true, "on")
  receive_relay_report(parent, children[4], 4, true)
  receive_relay_report(parent, children[1], 1, false)
  receive_relay_report(parent, children[4], 4, false, "off")
end)

test.register_coroutine_test("Unknown mode prevents all-off even when confirmed relays are off", function()
  for ep = 1, 3 do
    test.socket.zigbee:__expect_send({ parent.id, OnOff.attributes.OnOff:read(parent):to_endpoint(ep) })
    receive_mode_report(parent, ep, "switch")
    receive_relay_report(parent, children[ep], ep, false)
  end
  children[4]:expect_metadata_update({ profile = "scene-switch-child-scene" })
  expect_parent_switch(parent, "off")
  receive_mode_report(parent, 4, "scene")
end)

test.register_coroutine_test("Changing the only on relay to scene recomputes aggregate from remaining children", function()
  confirm_switch_modes()
  for ep = 1, 4 do
    receive_relay_report(parent, children[ep], ep, ep == 2, ep == 2 and "on" or nil)
  end
  children[2]:expect_metadata_update({ profile = "scene-switch-child-scene" })
  expect_parent_switch(parent, "off")
  receive_mode_report(parent, 2, "scene")
  receive_relay_report(parent, nil, 2, true)
  test.socket.capability:__expect_send(parent:generate_test_message("main",
    capabilities.button.button.pushed({ state_change = true })))
  test.socket.zigbee:__queue_receive({ parent.id,
    zb_utils.build_custom_command_id(parent, 0x0006, 0xFD, nil, "", 2) })
end)

test.register_coroutine_test("Physical scene presses still reach the parent when the child is unavailable", function()
  confirm_scene_modes()
  local actual = rawget(scene_parent, "wrapped_device")
  local get_child = actual.get_child_by_parent_assigned_key
  local original = rawget(actual, "get_child_by_parent_assigned_key")
  rawset(actual, "get_child_by_parent_assigned_key", function(self, key)
    if key == "04" then return nil end
    return get_child(self, key)
  end)
  test.socket.capability:__expect_send(scene_parent:generate_test_message("main",
    capabilities.button.button.pushed({ state_change = true })))
  test.socket.zigbee:__queue_receive({ scene_parent.id,
    zb_utils.build_custom_command_id(scene_parent, 0x0006, 0xFD, nil, "", 4) })
  test.wait_for_events()
  rawset(actual, "get_child_by_parent_assigned_key", original)
end)

test.register_coroutine_test("Reinitialization retains confirmed modes for parent routing", function()
  confirm_switch_modes()
  children[2]:expect_metadata_update({ profile = "scene-switch-child-scene" })
  receive_mode_report(parent, 2, "scene")
  expect_button_metadata(parent)
  test.socket.device_lifecycle:__queue_receive({ parent.id, "init" })
  test.wait_for_events()
  for _, ep in ipairs({ 1, 3, 4 }) do expect_relay_command(parent, ep, true) end
  send_switch_command(parent, "on")
end)

test.register_coroutine_test("A child added after its scene mode report adopts the confirmed profile", function()
  receive_mode_report(parent, 2, "scene")
  test.mock_device.add_test_device(children[2])
  children[2]:expect_metadata_update({ profile = "scene-switch-child-scene" })
  test.socket.device_lifecycle:__queue_receive({ children[2].id, "added" })
  test.wait_for_events()
  send_switch_command(children[2], "on")
  test.socket.capability:__expect_send(parent:generate_test_message("main",
    capabilities.button.button.pushed({ state_change = true })))
  test.socket.zigbee:__queue_receive({ parent.id,
    zb_utils.build_custom_command_id(parent, 0x0006, 0xFD, nil, "", 2) })
end, { test_init = function()
  test.mock_device.add_test_device(parent)
  expect_button_metadata(parent)
end })

test.register_coroutine_test("A late scene profile is corrected to the newer confirmed switch mode", function()
  confirm_switch_modes()
  children[2]:expect_metadata_update({ profile = "scene-switch-child-scene" })
  receive_mode_report(parent, 2, "scene")
  test.socket.zigbee:__expect_send({ parent.id, OnOff.attributes.OnOff:read(parent):to_endpoint(2) })
  receive_mode_report(parent, 2, "switch")

  local info = utils.deep_copy(children[2].raw_st_data)
  -- A profile completion preserves the current preferences; it is not a new mode request.
  info.preferences = utils.deep_copy(children[2].preferences)
  info.profile = utils.deep_copy(scene_children[2].raw_st_data.profile)
  expect_button_metadata(children[2])
  children[2]:expect_metadata_update({ profile = "scene-switch-child" })
  test.socket.device_lifecycle:__queue_receive({ children[2].id, "infoChanged", json.encode(info) })
  test.wait_for_events()
  receive_relay_report(parent, nil, 2, true)

  info.profile = utils.deep_copy(children[2].raw_st_data.profile)
  test.socket.zigbee:__expect_send({ parent.id, OnOff.attributes.OnOff:read(parent):to_endpoint(2) })
  test.socket.device_lifecycle:__queue_receive({ children[2].id, "infoChanged", json.encode(info) })
  test.wait_for_events()
  receive_relay_report(parent, children[2], 2, true, "on")
  expect_relay_command(parent, 2, false)
  send_switch_command(children[2], "off")
end)

test.register_coroutine_test("Returning to switch refreshes again when the child profile finishes", function()
  confirm_scene_modes()
  expect_button_metadata(scene_children[2])
  expect_mode_request(scene_parent, 2, "switch")
  test.socket.device_lifecycle:__queue_receive(scene_children[2]:generate_info_changed({
    preferences = { switchMode = "switch" }
  }))
  test.wait_for_events()
  send_switch_command(scene_children[2], "on")
  scene_children[2]:expect_metadata_update({ profile = "scene-switch-child" })
  test.socket.zigbee:__expect_send({ scene_parent.id, OnOff.attributes.OnOff:read(scene_parent):to_endpoint(2) })
  receive_mode_report(scene_parent, 2, "switch")
  receive_relay_report(scene_parent, nil, 2, true)
  local info = utils.deep_copy(scene_children[2].raw_st_data)
  info.preferences.switchMode = "switch"
  info.profile = utils.deep_copy(children[2].raw_st_data.profile)
  test.socket.zigbee:__expect_send({ scene_parent.id, OnOff.attributes.OnOff:read(scene_parent):to_endpoint(2) })
  test.socket.device_lifecycle:__queue_receive({ scene_children[2].id, "infoChanged", json.encode(info) })
  test.wait_for_events()
  receive_relay_report(scene_parent, scene_children[2], 2, true, "on")
end)

local function expect_reads(device, endpoint)
  for ep = endpoint or 1, endpoint or 4 do
    test.socket.zigbee:__expect_send({ device.id, OnOff.attributes.OnOff:read(device):to_endpoint(ep) })
    test.socket.zigbee:__expect_send({ device.id, enum_read(device, 0xD020, ep) })
  end
end

local function expect_configuration()
  test.socket.zigbee:__set_channel_ordering("relaxed")
  expect_reads(parent)
  for ep = 1, 4 do
    for _, cluster in ipairs({ OnOff.ID, 0xE001 }) do
      test.socket.zigbee:__expect_send({ parent.id,
        zb_utils.build_bind_request(parent, zb_utils.mock_hub_eui, cluster, ep):to_endpoint(ep) })
    end
    test.socket.zigbee:__expect_send({ parent.id,
      OnOff.attributes.OnOff:configure_reporting(parent, 0, 300):to_endpoint(ep) })
    test.socket.zigbee:__expect_send({ parent.id, cluster_base.configure_reporting(parent,
      data_types.ClusterId(0xE001), data_types.AttributeId(0xD020), data_types.Enum8.ID, 1, 3600):to_endpoint(ep) })
  end
  test.socket.zigbee:__expect_send({ parent.id, zb_utils.build_attribute_read(parent, 0x0000,
    { 0x0004, 0x0000, 0x0001, 0x0005, 0x0007, 0xFFFE }) })
  parent:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.register_coroutine_test("Tuya configuration binds and configures OnOff and D020 once per endpoint", function()
  expect_configuration()
  test.socket.device_lifecycle:__queue_receive({ parent.id, "doConfigure" })
end)

test.register_coroutine_test("Driver switch configures and provisions the aggregate parent", function()
  expect_configuration()
  test.socket.device_lifecycle:__queue_receive({ parent.id, "driverSwitched" })
end)

test.register_coroutine_test("Child configure has no Zigbee traffic and driver switch provisions both profiles", function()
  for _, device in ipairs({ children[2], scene_children[3] }) do
    device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.device_lifecycle:__queue_receive({ device.id, "doConfigure" })
    test.wait_for_events()
    device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.device_lifecycle:__queue_receive({ device.id, "driverSwitched" })
    test.wait_for_events()
  end
end)

test.register_coroutine_test("Inherited parent refresh reads OnOff and D020 without synthetic presses", function()
  confirm_scene_modes()
  test.socket.zigbee:__set_channel_ordering("relaxed")
  expect_reads(scene_parent)
  test.socket.capability:__queue_receive({ scene_parent.id,
    { capability = "refresh", component = "main", command = "refresh", args = {} } })
end)

test.register_coroutine_test("Inherited child refresh reads only its endpoint", function()
  test.socket.zigbee:__set_channel_ordering("relaxed")
  expect_reads(parent, 3)
  test.socket.capability:__queue_receive({ children[3].id,
    { capability = "refresh", component = "main", command = "refresh", args = {} } })
end)

local function build_default_response(device, ep, command_id, status)
  local body = default_response.DefaultResponse(command_id, status)
  return messages.ZigbeeMessageRx({
    address_header = messages.AddressHeader(device:get_short_address(), ep,
      constants.HUB.ADDR, constants.HUB.ENDPOINT, constants.HA_PROFILE_ID, OnOff.ID),
    body = zcl_messages.ZclMessageBody({
      zcl_header = zcl_messages.ZclHeader({ cmd = data_types.ZCLCommandId(body.ID) }), zcl_body = body,
    }),
  })
end

for _, on in ipairs({ true, false }) do
  local name = on and "on" or "off"
  local command_id = on and OnOff.server.commands.On.ID or OnOff.server.commands.Off.ID
  test.register_coroutine_test("Successful " .. name .. " DefaultResponse follows standard child routing and aggregation", function()
    confirm_switch_modes()
    for ep = 1, 4 do
      test.socket.capability:__expect_send(children[ep]:generate_test_message("main", capabilities.switch.switch(name)))
      if (on and ep == 1) or (not on and ep == 4) then expect_parent_switch(parent, name) end
      test.socket.zigbee:__queue_receive({ parent.id, build_default_response(parent, ep, command_id, Status.SUCCESS) })
      test.wait_for_events()
    end
  end)
  test.register_coroutine_test("Failed " .. name .. " DefaultResponse does not claim relay state", function()
    confirm_switch_modes()
    test.socket.zigbee:__queue_receive({ parent.id, build_default_response(parent, 2, command_id, Status.FAILURE) })
    test.wait_for_events()
    receive_relay_report(parent, children[2], 2, on, on and "on" or nil)
  end)
end

test.register_coroutine_test("Scene and unknown-mode DefaultResponses cannot emit switch events", function()
  test.socket.zigbee:__queue_receive({ parent.id,
    build_default_response(parent, 1, OnOff.server.commands.On.ID, Status.SUCCESS) })
  confirm_scene_modes()
  for ep = 1, 4 do
    test.socket.zigbee:__queue_receive({ scene_parent.id,
      build_default_response(scene_parent, ep, OnOff.server.commands.On.ID, Status.SUCCESS) })
  end
end)

test.register_coroutine_test("Unrelated successful DefaultResponse does not claim relay state", function()
  confirm_switch_modes()
  test.socket.zigbee:__queue_receive({ parent.id,
    build_default_response(parent, 1, OnOff.server.commands.Toggle.ID, Status.SUCCESS) })
end)

test.run_registered_tests()
