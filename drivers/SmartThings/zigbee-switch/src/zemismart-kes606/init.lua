-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local device_lib = require "st.device"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local switch_defaults = require "st.zigbee.defaults.switch_defaults"
local default_response = require "st.zigbee.zcl.global_commands.default_response"
local find_child = require "lifecycle_handlers.find_child"

local OnOff = clusters.OnOff
local SWITCH_PROFILE = "scene-switch-child"
local SCENE_PROFILE = "scene-switch-child-scene"
local MODE_CLUSTER = 0xE001
local MODE_ATTRIBUTE = 0xD020
local POWER_ON_ATTRIBUTE = 0xD010
local LIGHT_ATTRIBUTE = 0x8001
local GLOBAL_POWER_ON_ATTRIBUTE = 0x8002
local SCENE_PRESS_COMMAND = 0xFD
local LIGHT_VALUES = { none = 0, relay = 1, pos = 2 }
local POWER_ON_VALUES = { off = 0, on = 1, memory = 2 }

local function valid_endpoint(endpoint)
  return endpoint ~= nil and endpoint >= 1 and endpoint <= 4
end

local function mode_field(endpoint)
  return string.format("mode_gang_%d", endpoint)
end

local function is_relay(parent, child)
  local endpoint = child and child:get_endpoint()
  return parent ~= nil and valid_endpoint(endpoint)
    and parent:get_field(mode_field(endpoint)) == "switch"
end

local function update_parent_switch(parent)
  local state, unknown = "off", false
  for endpoint = 1, 4 do
    local mode = parent:get_field(mode_field(endpoint))
    if mode == "switch" then
      local child = find_child(parent, endpoint)
      local child_state = child and child:get_latest_state("main", "switch", "switch")
      if child_state == "on" then
        state = "on"
        break
      end
      if child_state == nil then unknown = true end
    elseif mode == nil then
      unknown = true
    end
  end
  -- Use the children's last known states; an unknown relay cannot establish all-off.
  if state == "off" and unknown then return end
  if parent:get_latest_state("main", "switch", "switch") ~= state then
    parent:emit_event(capabilities.switch.switch(state))
  end
end

local function initialize_button(device)
  if device:supports_capability(capabilities.button) then
    device:emit_event(capabilities.button.supportedButtonValues(
      { "pushed" }, { visibility = { displayed = false } }))
    device:emit_event(capabilities.button.numberOfButtons(
      { value = 1 }, { visibility = { displayed = false } }))
  end
end

local function sync_child_profile(parent, child)
  local mode = parent:get_field(mode_field(child:get_endpoint()))
  if mode == nil then return end
  local capability = mode == "scene" and capabilities.button or capabilities.switch
  if not child:supports_capability(capability) then
    child:try_update_metadata({ profile = mode == "scene" and SCENE_PROFILE or SWITCH_PROFILE })
  end
end

local function ensure_children(driver, parent)
  for endpoint = 1, 4 do
    if find_child(parent, endpoint) == nil then
      driver:try_create_device({
        type = "EDGE_CHILD",
        parent_device_id = parent.id,
        parent_assigned_child_key = string.format("%02X", endpoint),
        label = string.format("%s L%d", parent.label, endpoint),
        profile = parent:get_field(mode_field(endpoint)) == "scene" and SCENE_PROFILE or SWITCH_PROFILE,
      })
    end
  end
end

local function device_init(_, device)
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
    device:add_configured_attribute({
      cluster = MODE_CLUSTER,
      attribute = MODE_ATTRIBUTE,
      minimum_interval = 1,
      maximum_interval = 3600,
      data_type = data_types.Enum8,
    })
  end
  initialize_button(device)
end

local function device_added(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    ensure_children(driver, device)
  else
    local parent = device:get_parent_device()
    if parent ~= nil and valid_endpoint(device:get_endpoint()) then
      sync_child_profile(parent, device)
      if is_relay(parent, device) then device:send(OnOff.attributes.OnOff:read(device)) end
    end
  end
end

local function switch_command(handler)
  return function(driver, device, command)
    if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
      for endpoint = 1, 4 do
        local child = find_child(device, endpoint)
        if is_relay(device, child) and child:supports_capability(capabilities.switch) then
          handler(driver, child, command, false)
        end
      end
    elseif is_relay(device:get_parent_device(), device) and device:supports_capability(capabilities.switch) then
      handler(driver, device, command, false)
    end
  end
end

local function onoff_report(driver, device, value, zb_rx)
  local child = find_child(device, zb_rx.address_header.src_endpoint.value)
  if is_relay(device, child) and child:supports_capability(capabilities.switch) then
    -- Native handling would bypass the parent aggregation below.
    switch_defaults.on_off_attr_handler(driver, device, value, zb_rx, false)
    update_parent_switch(device)
  end
end

local function onoff_default_response(driver, device, zb_rx)
  local child = find_child(device, zb_rx.address_header.src_endpoint.value)
  if is_relay(device, child) and child:supports_capability(capabilities.switch) then
    switch_defaults.default_response_handler(driver, device, zb_rx, false)
    update_parent_switch(device)
  end
end

local function mode_report(_, device, value, zb_rx)
  local endpoint = zb_rx.address_header.src_endpoint.value
  if not valid_endpoint(endpoint) or (value.value ~= 0 and value.value ~= 1) then return end
  local mode = value.value == 1 and "scene" or "switch"
  local previous = device:get_field(mode_field(endpoint))
  -- D020 readback is the single mode source; preferences only request a change.
  device:set_field(mode_field(endpoint), mode, { persist = true })
  local child = find_child(device, endpoint)
  if child ~= nil then
    sync_child_profile(device, child)
    if mode == "switch" and previous ~= mode then
      child:send(OnOff.attributes.OnOff:read(child))
    end
  end
  update_parent_switch(device)
end

local function scene_command(_, device, zb_rx)
  local endpoint = zb_rx.address_header.src_endpoint.value
  if not valid_endpoint(endpoint) or device:get_field(mode_field(endpoint)) ~= "scene" then return end
  local child = find_child(device, endpoint)
  if child ~= nil and child:supports_capability(capabilities.button) then
    child:emit_event(capabilities.button.button.pushed({ state_change = true }))
  end
  device:emit_event(capabilities.button.button.pushed({ state_change = true }))
end

local function driver_switched(driver, device)
  -- The SDK checks root supported_capabilities, which does not include button.
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    ensure_children(driver, device)
    require("tuya-multi").lifecycle_handlers.doConfigure(driver, device)
  end
  device:try_update_metadata({ provisioning_state = "PROVISIONED" })
end

local function changed(preferences, old_preferences, name)
  return preferences[name] ~= nil and preferences[name] ~= old_preferences[name]
end

local function write_enum(device, cluster, attribute, value, endpoint)
  local message = cluster_base.write_attribute(device, data_types.ClusterId(cluster),
    data_types.AttributeId(attribute), data_types.Enum8(value))
  if endpoint ~= nil then message:to_endpoint(endpoint) end
  device:send(message)
end

local function update_parent_preferences(device, old_preferences)
  local preferences = device.preferences or {}
  if changed(preferences, old_preferences, "lightMode") then
    local value = LIGHT_VALUES[preferences.lightMode]
    if value ~= nil then write_enum(device, OnOff.ID, LIGHT_ATTRIBUTE, value, 1) end
  end
  if changed(preferences, old_preferences, "relayStatus") then
    local value = POWER_ON_VALUES[preferences.relayStatus]
    if value ~= nil then write_enum(device, OnOff.ID, GLOBAL_POWER_ON_ATTRIBUTE, value, 1) end
  end
  for endpoint = 1, 4 do
    local name = string.format("relayStatus%d", endpoint)
    local value = POWER_ON_VALUES[preferences[name]]
    if changed(preferences, old_preferences, name) and value ~= nil then
      write_enum(device, MODE_CLUSTER, POWER_ON_ATTRIBUTE, value, endpoint)
    end
  end
end

local function info_changed(_, device, _, args)
  local old_store = args and args.old_st_store or {}
  local old_preferences = old_store.preferences or {}
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    update_parent_preferences(device, old_preferences)
    return
  end
  local parent = device:get_parent_device()
  local endpoint = device:get_endpoint()
  if parent == nil or not valid_endpoint(endpoint) then return end
  initialize_button(device)
  local preferences = device.preferences or {}
  local mode = preferences.switchMode
  if changed(preferences, old_preferences, "switchMode") and (mode == "switch" or mode == "scene") then
    write_enum(device, MODE_CLUSTER, MODE_ATTRIBUTE, mode == "scene" and 1 or 0)
    device:send(cluster_base.read_attribute(device,
      data_types.ClusterId(MODE_CLUSTER), data_types.AttributeId(MODE_ATTRIBUTE)))
  end
  if changed(preferences, old_preferences, "countdownSeconds") then
    local seconds = tonumber(preferences.countdownSeconds)
    if seconds ~= nil and seconds == seconds then
      seconds = math.max(0, math.min(43200, math.floor(seconds)))
      device:send(OnOff.server.commands.OnWithTimedOff(
        device, data_types.Uint8(0), data_types.Uint16(seconds), data_types.Uint16(seconds)))
    end
  end
  -- Reconcile a delayed profile update against the latest D020 mode.
  sync_child_profile(parent, device)
  if old_store.profile ~= nil and old_store.profile.id ~= device.profile.id
      and is_relay(parent, device) and device:supports_capability(capabilities.switch) then
    -- A read received while the old button profile was active could not emit switch state.
    device:send(OnOff.attributes.OnOff:read(device))
  end
end

return {
  NAME = "Zemismart KES606 Four Gang",
  supported_capabilities = { capabilities.refresh, capabilities.switch, capabilities.button },
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
    driverSwitched = driver_switched,
    infoChanged = info_changed,
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_command(switch_defaults.on),
      [capabilities.switch.commands.off.NAME] = switch_command(switch_defaults.off),
    },
  },
  zigbee_handlers = {
    global = { [OnOff.ID] = { [default_response.DefaultResponse.ID] = onoff_default_response } },
    attr = {
      [OnOff.ID] = { [OnOff.attributes.OnOff.ID] = onoff_report },
      [MODE_CLUSTER] = { [MODE_ATTRIBUTE] = mode_report },
    },
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.On.ID] = scene_command,
        [OnOff.server.commands.Off.ID] = scene_command,
        [OnOff.server.commands.Toggle.ID] = scene_command,
        [SCENE_PRESS_COMMAND] = scene_command,
      },
    },
  },
  can_handle = require("zemismart-kes606.can_handle"),
}
