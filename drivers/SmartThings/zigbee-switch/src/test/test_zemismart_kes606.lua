-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
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

local PARENT_PROFILE = "ts0601-scene-switch-4-gang.yml"
local SWITCH_PROFILE = "ts0601-scene-switch-child.yml"
local SCENE_PROFILE = "ts0601-scene-switch-child-scene.yml"

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
      profile = t_utils.get_profile_definition(profile),
      parent_device_id = parent.id, parent_assigned_child_key = "gang" .. ep,
      label = parent.label .. " L" .. ep,
    })
  end
  return children
end

local parent = make_parent("Relay sample")
local children = make_children(parent, SWITCH_PROFILE)
local scene_parent = make_parent("Scene sample")
local scene_children = make_children(scene_parent, SCENE_PROFILE)

zb_utils.prepare_zigbee_env_info()


local function expect_button_metadata(child)
  test.socket.capability:__expect_send(child:generate_test_message("main",
    capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(child:generate_test_message("main",
    capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })))
end

test.set_test_init_function(function()
  test.mock_device.add_test_device(parent)
  test.mock_device.add_test_device(scene_parent)
  test.socket.capability:__set_channel_ordering("relaxed")
  for ep = 1, 4 do
    test.mock_device.add_test_device(children[ep])
    test.mock_device.add_test_device(scene_children[ep])
    expect_button_metadata(scene_children[ep])
  end
end)

local function enum_write(attribute, value, ep, cluster)
  return cluster_base.write_attribute(parent, data_types.ClusterId(cluster or 0xE001),
    data_types.AttributeId(attribute), data_types.Enum8(value)):to_endpoint(ep)
end

test.register_coroutine_test("Only the exact four-gang fingerprint uses the composite handler", function()
  local matches = require "zemismart-kes606.can_handle"
  assert(matches({}, nil, parent))
  for ep = 1, 4 do assert(matches({}, nil, children[ep])) end
  local other = test.mock_device.build_test_zigbee_device({
    manufacturer = "_TZ3000_other", model = "TS0726",
    profile = t_utils.get_profile_definition(PARENT_PROFILE),
  })
  assert(not matches({}, nil, other))
  local other_model = test.mock_device.build_test_zigbee_device({
    manufacturer = "_TZ3000_hurauima", model = "TS0004",
    profile = t_utils.get_profile_definition(PARENT_PROFILE),
  })
  assert(not matches({}, nil, other_model))
  assert(not matches({}, nil, nil))
  assert(not require("tuya-multi.can_handle")({}, nil, parent))
end)

test.register_coroutine_test("Repeated parent initialization does not recreate children", function()
  test.socket.device_lifecycle:__queue_receive({ parent.id, "init" })
  test.wait_for_events()
  test.socket.device_lifecycle:__queue_receive({ parent.id, "init" })
end)

test.register_coroutine_test("Restored scene children initialize metadata without button presses", function()
  for ep = 1, 4 do
    expect_button_metadata(scene_children[ep])
    test.socket.device_lifecycle:__queue_receive({ scene_children[ep].id, "init" })
  end
end)

for ep = 1, 4 do
  for _, on in ipairs({ true, false }) do
    local command_name = on and "on" or "off"
    test.register_message_test("Relay " .. ep .. " " .. command_name .. " routes to its endpoint", {
      { channel = "capability", direction = "receive", message = {
        children[ep].id, { capability = "switch", component = "main",
          command = command_name, args = {} }
      } },
      { channel = "zigbee", direction = "send", message = {
        parent.id, (on and OnOff.server.commands.On(parent)
          or OnOff.server.commands.Off(parent)):to_endpoint(ep)
      } },
    })
    test.register_message_test("Relay report " .. ep .. " " .. command_name .. " reaches only its child", {
      { channel = "zigbee", direction = "receive", message = {
        parent.id, OnOff.attributes.OnOff:build_test_attr_report(parent, on):from_endpoint(ep)
      } },
      { channel = "capability", direction = "send", message =
        children[ep]:generate_test_message("main", capabilities.switch.switch(command_name)) },
    })
  end

  test.register_coroutine_test("Scene " .. ep .. " ignores relay attributes and relay commands", function()
    test.socket.zigbee:__queue_receive({ scene_parent.id,
      OnOff.attributes.OnOff:build_test_attr_report(scene_parent, false):from_endpoint(ep) })
    test.socket.capability:__queue_receive({ scene_children[ep].id,
      { capability = "switch", component = "main", command = "on", args = {} } })
  end)

  test.register_coroutine_test("Scene command 0xFD on endpoint " .. ep .. " emits one pushed event", function()
    expect_button_metadata(scene_children[ep])
    test.socket.capability:__expect_send(scene_children[ep]:generate_test_message("main",
      capabilities.button.button.pushed({ state_change = true })))
    test.socket.zigbee:__queue_receive({ scene_parent.id,
      zb_utils.build_custom_command_id(scene_parent, 0x0006, 0xFD, nil, "", ep) })
  end)

  test.register_coroutine_test("Relay " .. ep .. " ignores scene commands", function()
    test.socket.zigbee:__queue_receive({ parent.id,
      zb_utils.build_custom_command_id(parent, 0x0006, 0xFD, nil, "", ep) })
  end)

  test.register_coroutine_test("Mode setting for child " .. ep .. " targets only that gang", function()
    children[ep]:expect_metadata_update({ profile = "ts0601-scene-switch-child-scene" })
    test.socket.zigbee:__expect_send({ parent.id, enum_write(0xD020, 1, ep) })
    test.socket.device_lifecycle:__queue_receive(children[ep]:generate_info_changed({
      preferences = { switchMode = "scene" }
    }))
  end)

  test.register_coroutine_test("Device mode report for gang " .. ep .. " updates the correct profile", function()
    children[ep]:expect_metadata_update({ profile = "ts0601-scene-switch-child-scene" })
    test.socket.zigbee:__queue_receive({ parent.id, zb_utils.build_attribute_report(parent,
      0xE001, { { 0xD020, data_types.Enum8.ID, 1 } }):from_endpoint(ep) })
  end)

  test.register_coroutine_test("Scene child " .. ep .. " can return to relay mode", function()
    expect_button_metadata(scene_children[ep])
    scene_children[ep]:expect_metadata_update({ profile = "ts0601-scene-switch-child" })
    test.socket.zigbee:__expect_send({ scene_parent.id, cluster_base.write_attribute(scene_parent,
      data_types.ClusterId(0xE001), data_types.AttributeId(0xD020), data_types.Enum8(0)):to_endpoint(ep) })
    test.socket.device_lifecycle:__queue_receive(scene_children[ep]:generate_info_changed({
      preferences = { switchMode = "switch" }
    }))
  end)

  test.register_coroutine_test("Countdown for gang " .. ep .. " uses the selected endpoint", function()
    test.socket.zigbee:__expect_send({ parent.id, OnOff.server.commands.OnWithTimedOff(parent,
      data_types.Uint8(0), data_types.Uint16(30), data_types.Uint16(30)):to_endpoint(ep) })
    test.socket.device_lifecycle:__queue_receive(children[ep]:generate_info_changed({
      preferences = { countdownSeconds = 30 }
    }))
  end)
end

test.register_coroutine_test("Invalid mode report cannot select an unsupported profile", function()
  test.socket.zigbee:__queue_receive({ parent.id, zb_utils.build_attribute_report(parent,
    0xE001, { { 0xD020, data_types.Enum8.ID, 2 } }):from_endpoint(1) })
end)

test.register_coroutine_test("Indicator and power-on settings use their documented attributes", function()
  test.socket.zigbee:__expect_send({ parent.id, enum_write(0x8001, 2, 1, 0x0006) })
  test.socket.zigbee:__expect_send({ parent.id, enum_write(0x8002, 0, 1, 0x0006) })
  test.socket.zigbee:__expect_send({ parent.id, enum_write(0xD010, 1, 3) })
  test.socket.device_lifecycle:__queue_receive(parent:generate_info_changed({
    preferences = { lightMode = "pos", relayStatus = "off", relayStatus3 = "on" }
  }))
end)

test.register_coroutine_test("Switch profile completion refreshes a report lost during mode transition", function()
  local child = scene_children[2]
  expect_button_metadata(child)
  child:expect_metadata_update({ profile = "ts0601-scene-switch-child" })
  test.socket.zigbee:__expect_send({ scene_parent.id, cluster_base.write_attribute(scene_parent,
    data_types.ClusterId(0xE001), data_types.AttributeId(0xD020), data_types.Enum8(0)):to_endpoint(2) })
  test.socket.device_lifecycle:__queue_receive(child:generate_info_changed({
    preferences = { switchMode = "switch" }
  }))
  test.wait_for_events()
  test.socket.zigbee:__queue_receive({ scene_parent.id,
    OnOff.attributes.OnOff:build_test_attr_report(scene_parent, false):from_endpoint(2) })
  test.wait_for_events()
  test.socket.zigbee:__expect_send({ scene_parent.id,
    OnOff.attributes.OnOff:read(scene_parent):to_endpoint(2) })
  -- Replace the profile, rather than deep-merging its capability map with the old button profile.
  local device_info = utils.deep_copy(child.raw_st_data)
  device_info.preferences.switchMode = "switch"
  device_info.profile = utils.deep_copy(children[2].raw_st_data.profile)
  test.socket.device_lifecycle:__queue_receive({ child.id, "infoChanged", json.encode(device_info) })
  test.wait_for_events()
  test.socket.capability:__expect_send(child:generate_test_message("main",
    capabilities.switch.switch.off()))
  test.socket.zigbee:__queue_receive({ scene_parent.id,
    OnOff.attributes.OnOff:build_test_attr_report(scene_parent, false):from_endpoint(2) })
end)

local function expect_reads(device, scene)
  for ep = 1, 4 do
    if not scene then
      test.socket.zigbee:__expect_send({ device.id, OnOff.attributes.OnOff:read(device):to_endpoint(ep) })
    end
    for _, attribute in ipairs({ 0xD020, 0xD010 }) do
      test.socket.zigbee:__expect_send({ device.id, cluster_base.read_attribute(device,
        data_types.ClusterId(0xE001), data_types.AttributeId(attribute)):to_endpoint(ep) })
    end
  end
  for _, attribute in ipairs({ 0x8001, 0x8002 }) do
    test.socket.zigbee:__expect_send({ device.id, cluster_base.read_attribute(device,
      data_types.ClusterId(0x0006), data_types.AttributeId(attribute)):to_endpoint(1) })
  end
end

local function expect_configuration()
  test.socket.zigbee:__set_channel_ordering("relaxed")
  test.socket.zigbee:__expect_send({ parent.id, zb_utils.build_attribute_read(parent, 0x0000,
    { 0x0004, 0x0000, 0x0001, 0x0005, 0x0007, 0xFFFE }) })
  for ep = 1, 4 do
    test.socket.zigbee:__expect_send({ parent.id,
      zb_utils.build_bind_request(parent, zb_utils.mock_hub_eui, OnOff.ID, ep) })
    test.socket.zigbee:__expect_send({ parent.id,
      OnOff.attributes.OnOff:configure_reporting(parent, 0, 300, 1):to_endpoint(ep) })
    for _, attribute in ipairs({ 0xD020, 0xD010 }) do
      test.socket.zigbee:__expect_send({ parent.id, cluster_base.configure_reporting(parent,
        data_types.ClusterId(0xE001), data_types.AttributeId(attribute),
        data_types.Enum8.ID, 1, 3600, 1):to_endpoint(ep) })
    end
  end
  for _, attribute in ipairs({ 0x8001, 0x8002 }) do
    test.socket.zigbee:__expect_send({ parent.id, cluster_base.configure_reporting(parent,
      data_types.ClusterId(0x0006), data_types.AttributeId(attribute),
      data_types.Enum8.ID, 1, 3600, 1):to_endpoint(1) })
  end
  expect_reads(parent, false)
  parent:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.register_coroutine_test("Configure binds all four endpoints without generic Tuya duplication", function()
  expect_configuration()
  test.socket.device_lifecycle:__queue_receive({ parent.id, "doConfigure" })
end)

test.register_coroutine_test("Driver switch provisions the refresh-only parent using its own configuration", function()
  expect_configuration()
  test.socket.device_lifecycle:__queue_receive({ parent.id, "driverSwitched" })
end)

for ep = 1, 4 do
  test.register_coroutine_test("Driver switch provisions relay child " .. ep, function()
    children[ep]:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.device_lifecycle:__queue_receive({ children[ep].id, "driverSwitched" })
  end)
  test.register_coroutine_test("Driver switch provisions scene child " .. ep .. " without a press", function()
    expect_button_metadata(scene_children[ep])
    scene_children[ep]:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.device_lifecycle:__queue_receive({ scene_children[ep].id, "driverSwitched" })
  end)
end

test.register_coroutine_test("Scene refresh reads settings without relay reads or synthetic presses", function()
  test.socket.zigbee:__set_channel_ordering("relaxed")
  test.socket.zigbee:__expect_send({ scene_parent.id, zb_utils.build_attribute_read(scene_parent,
    0x0000, { 0x0004, 0x0000, 0x0001, 0x0005, 0x0007, 0xFFFE }) })
  expect_reads(scene_parent, true)
  test.socket.capability:__queue_receive({ scene_parent.id,
    { capability = "refresh", component = "main", command = "refresh", args = {} } })
end)

test.register_coroutine_test("Initialization creates exactly four relay children", function() end, {
  test_init = function()
    test.mock_device.add_test_device(parent)
    for ep = 1, 4 do
      parent:expect_device_create({ type = "EDGE_CHILD", parent_device_id = parent.id,
        parent_assigned_child_key = "gang" .. ep, label = parent.label .. " L" .. ep,
        profile = "ts0601-scene-switch-child" })
    end
  end,
})

local function build_onoff_default_response(device, endpoint, command_id, status)
  local body = default_response.DefaultResponse(command_id, status)
  return messages.ZigbeeMessageRx({
    address_header = messages.AddressHeader(device:get_short_address(), endpoint,
      constants.HUB.ADDR, constants.HUB.ENDPOINT, constants.HA_PROFILE_ID, OnOff.ID),
    body = zcl_messages.ZclMessageBody({
      zcl_header = zcl_messages.ZclHeader({ cmd = data_types.ZCLCommandId(body.ID) }),
      zcl_body = body,
    }),
  })
end

for _, scene in ipairs({ false, true }) do
  local sample = scene and scene_parent or parent
  local mode_name = scene and "scene" or "relay"
  for ep = 1, 4 do
    for _, on in ipairs({ true, false }) do
      local command_id = on and OnOff.server.commands.On.ID or OnOff.server.commands.Off.ID
      local command_name = on and "on" or "off"
      for _, success in ipairs({ true, false }) do
        local status = success and Status.SUCCESS or Status.FAILURE
        local status_name = success and "success" or "failure"
        test.register_coroutine_test("DefaultResponse " .. mode_name .. " " .. ep .. " "
          .. command_name .. " " .. status_name .. " never claims parent state or native routing", function()
          -- Unsupported parent events are silently discarded by the SDK. Observe only this test's
          -- real device instance before that guard, so a generic parent handler cannot pass unnoticed.
          local actual = rawget(sample, "wrapped_device")
          local emit = actual.emit_component_event
          local raw_emit = rawget(actual, "emit_component_event")
          local raw_register = rawget(actual, "register_native_capability_attr_handler")
          local parent_events, native_registrations = 0, 0
          rawset(actual, "emit_component_event", function(self, ...)
            parent_events = parent_events + 1
            return emit(self, ...)
          end)
          rawset(actual, "register_native_capability_attr_handler", function()
            native_registrations = native_registrations + 1
          end)

          test.socket.zigbee:__queue_receive({ sample.id,
            build_onoff_default_response(sample, ep, command_id, status) })
          test.wait_for_events()
          -- A real report remains authoritative, even after a failed command response.
          if not scene then
            test.socket.capability:__expect_send(children[ep]:generate_test_message("main",
              capabilities.switch.switch(command_name)))
          end
          test.socket.zigbee:__queue_receive({ sample.id,
            OnOff.attributes.OnOff:build_test_attr_report(sample, on):from_endpoint(ep) })
          test.wait_for_events()

          rawset(actual, "emit_component_event", raw_emit)
          rawset(actual, "register_native_capability_attr_handler", raw_register)
          assert(parent_events == 0 and native_registrations == 0,
            string.format("DefaultResponse leaked to generic parent handling: %d parent events, %d native registrations",
              parent_events, native_registrations))
        end)
      end
    end
  end
end

test.run_registered_tests()
