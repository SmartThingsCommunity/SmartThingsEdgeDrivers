-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local device_lib = require "st.device"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local device_management = require "st.zigbee.device_management"
local zcl_messages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"
local read_attribute = require "st.zigbee.zcl.global_commands.read_attribute"

local OnOff = clusters.OnOff
local SWITCH_PROFILE = "ts0601-scene-switch-child"
local SCENE_PROFILE = "ts0601-scene-switch-child-scene"
local MODE_CLUSTER = 0xE001
local MODE_ATTRIBUTE = 0xD020
local POWER_ON_ATTRIBUTE = 0xD010
local LIGHT_ATTRIBUTE = 0x8001
local GLOBAL_POWER_ON_ATTRIBUTE = 0x8002
local SCENE_PRESS_COMMAND = 0xFD
local LIGHT_VALUES = { none = 0, relay = 1, pos = 2 }
local POWER_ON_VALUES = { off = 0, on = 1, memory = 2 }

local function parent_from_device(device)
  if device.network_type == device_lib.NETWORK_TYPE_CHILD then
    return device:get_parent_device()
  end
  return device
end

local function child_gang(device)
  if device.network_type ~= device_lib.NETWORK_TYPE_CHILD then return nil end
  return tonumber((device.parent_assigned_child_key or ""):match("^gang([1-4])$"))
end

local function get_child(parent, gang)
  return parent:get_child_by_parent_assigned_key(string.format("gang%d", gang))
end

local function mode_field(gang)
  return string.format("mode_gang_%d", gang)
end

local function gang_mode(parent, gang)
  local mode = parent:get_field(mode_field(gang))
  if mode ~= nil then return mode end
  local child = get_child(parent, gang)
  if child ~= nil and child:supports_capability(capabilities.button)
      and not child:supports_capability(capabilities.switch) then
    return "scene"
  end
  return "switch"
end

local function profile_for_mode(mode)
  return mode == "scene" and SCENE_PROFILE or SWITCH_PROFILE
end

local function initialize_button(child)
  if child:supports_capability(capabilities.button) then
    child:emit_event(capabilities.button.supportedButtonValues(
      { "pushed" }, { visibility = { displayed = false } }))
    child:emit_event(capabilities.button.numberOfButtons(
      { value = 1 }, { visibility = { displayed = false } }))
  end
  -- Initialization and profile transitions must never synthesize a button press.
end

local function set_child_profile(child, mode)
  local capability = mode == "scene" and capabilities.button or capabilities.switch
  if not child:supports_capability(capability) then
    child:try_update_metadata({ profile = profile_for_mode(mode) })
  end
end

local function ensure_children(driver, parent)
  for gang = 1, 4 do
    local child = get_child(parent, gang)
    local mode = gang_mode(parent, gang)
    if child == nil then
      driver:try_create_device({
        type = "EDGE_CHILD",
        parent_device_id = parent.id,
        parent_assigned_child_key = string.format("gang%d", gang),
        label = string.format("%s L%d", parent.label or "Zemismart KES606", gang),
        profile = profile_for_mode(mode),
      })
    else
      parent:set_field(mode_field(gang), mode, { persist = true })
      set_child_profile(child, mode)
    end
  end
end

local function endpoint_from_rx(zb_rx)
  local header = zb_rx and zb_rx.address_header
  local endpoint = header and header.src_endpoint and header.src_endpoint.value
  if endpoint ~= nil and endpoint >= 1 and endpoint <= 4 then return endpoint end
end

local function send_magic_spell(parent)
  local zclh = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(read_attribute.ReadAttribute.ID)
  })
  parent:send(messages.ZigbeeMessageTx({
    address_header = messages.AddressHeader(
      zb_const.HUB.ADDR, zb_const.HUB.ENDPOINT, parent:get_short_address(),
      parent:get_endpoint(clusters.Basic.ID) or 1, zb_const.HA_PROFILE_ID, clusters.Basic.ID
    ),
    body = zcl_messages.ZclMessageBody({
      zcl_header = zclh,
      zcl_body = read_attribute.ReadAttribute({ 0x0004, 0x0000, 0x0001, 0x0005, 0x0007, 0xFFFE })
    })
  }))
end

local function read_enum(parent, cluster_id, attribute_id, gang)
  parent:send(cluster_base.read_attribute(
    parent, data_types.ClusterId(cluster_id), data_types.AttributeId(attribute_id)
  ):to_endpoint(gang))
end

local function write_enum(parent, cluster_id, attribute_id, gang, value)
  parent:send(cluster_base.write_attribute(
    parent, data_types.ClusterId(cluster_id), data_types.AttributeId(attribute_id),
    data_types.Enum8(value)
  ):to_endpoint(gang))
end

local function configure_enum(parent, cluster_id, attribute_id, gang)
  parent:send(cluster_base.configure_reporting(
    parent, data_types.ClusterId(cluster_id), data_types.AttributeId(attribute_id),
    data_types.Enum8.ID, 1, 3600, 1
  ):to_endpoint(gang))
end

local function read_gang(parent, gang)
  if gang_mode(parent, gang) ~= "scene" then
    parent:send(OnOff.attributes.OnOff:read(parent):to_endpoint(gang))
  end
  read_enum(parent, MODE_CLUSTER, MODE_ATTRIBUTE, gang)
  read_enum(parent, MODE_CLUSTER, POWER_ON_ATTRIBUTE, gang)
  if gang == 1 then
    read_enum(parent, OnOff.ID, LIGHT_ATTRIBUTE, 1)
    read_enum(parent, OnOff.ID, GLOBAL_POWER_ON_ATTRIBUTE, 1)
  end
end

local function refresh(driver, device)
  local parent = parent_from_device(device)
  if parent == nil then return end
  send_magic_spell(parent)
  ensure_children(driver, parent)
  for gang = 1, 4 do read_gang(parent, gang) end
end

local function relay_command(device, on)
  local gang = child_gang(device)
  local parent = parent_from_device(device)
  if gang == nil or parent == nil or gang_mode(parent, gang) == "scene" then return end
  local command = on and OnOff.server.commands.On(parent) or OnOff.server.commands.Off(parent)
  parent:send(command:to_endpoint(gang))
end

local function onoff_report(_, device, value, zb_rx)
  local gang = endpoint_from_rx(zb_rx)
  local parent = parent_from_device(device)
  if gang == nil or parent == nil or gang_mode(parent, gang) == "scene" then return end
  local child = get_child(parent, gang)
  if child ~= nil and child:supports_capability(capabilities.switch) then
    local state = (value.value == true or value.value == 1) and "on" or "off"
    child:emit_event(capabilities.switch.switch(state))
  end
end

local function mode_report(_, device, value, zb_rx)
  local gang = endpoint_from_rx(zb_rx)
  local parent = parent_from_device(device)
  if gang == nil or parent == nil or (value.value ~= 0 and value.value ~= 1) then return end
  local mode = value.value == 1 and "scene" or "switch"
  parent:set_field(mode_field(gang), mode, { persist = true })
  local child = get_child(parent, gang)
  if child ~= nil then
    set_child_profile(child, mode)
    initialize_button(child)
  end
end

local function power_on_report(_, device, value, zb_rx)
  local gang = endpoint_from_rx(zb_rx)
  local parent = parent_from_device(device)
  if gang ~= nil and parent ~= nil then
    parent:set_field(string.format("relay_status_gang_%d", gang), value.value, { persist = true })
  end
end

local function light_report(_, device, value)
  local parent = parent_from_device(device)
  if parent ~= nil then parent:set_field("light_mode", value.value, { persist = true }) end
end

local function global_power_on_report(_, device, value)
  local parent = parent_from_device(device)
  if parent ~= nil then parent:set_field("relay_status", value.value, { persist = true }) end
end

local function scene_command(_, device, zb_rx)
  local gang = endpoint_from_rx(zb_rx)
  local parent = parent_from_device(device)
  if gang == nil or parent == nil or gang_mode(parent, gang) ~= "scene" then return end
  local child = get_child(parent, gang)
  if child ~= nil and child:supports_capability(capabilities.button) then
    initialize_button(child)
    child:emit_event(capabilities.button.button.pushed({ state_change = true }))
  end
end

local function initialize(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    ensure_children(driver, device)
  else
    initialize_button(device)
  end
end

local function do_configure(driver, device)
  if device.network_type ~= device_lib.NETWORK_TYPE_ZIGBEE then return end
  send_magic_spell(device)
  ensure_children(driver, device)
  for gang = 1, 4 do
    device:send(device_management.build_bind_request(
      device, OnOff.ID, driver.environment_info.hub_zigbee_eui, gang))
    device:send(OnOff.attributes.OnOff:configure_reporting(device, 0, 300, 1):to_endpoint(gang))
    configure_enum(device, MODE_CLUSTER, MODE_ATTRIBUTE, gang)
    configure_enum(device, MODE_CLUSTER, POWER_ON_ATTRIBUTE, gang)
    if gang == 1 then
      configure_enum(device, OnOff.ID, LIGHT_ATTRIBUTE, 1)
      configure_enum(device, OnOff.ID, GLOBAL_POWER_ON_ATTRIBUTE, 1)
    end
    read_gang(device, gang)
  end
end

local function changed(preferences, old_preferences, name)
  return preferences[name] ~= nil and preferences[name] ~= old_preferences[name]
end

local function update_parent_preferences(device, old_preferences)
  local preferences = device.preferences or {}
  if changed(preferences, old_preferences, "lightMode") then
    local value = LIGHT_VALUES[preferences.lightMode]
    if value ~= nil then write_enum(device, OnOff.ID, LIGHT_ATTRIBUTE, 1, value) end
  end
  if changed(preferences, old_preferences, "relayStatus") then
    local value = POWER_ON_VALUES[preferences.relayStatus]
    if value ~= nil then write_enum(device, OnOff.ID, GLOBAL_POWER_ON_ATTRIBUTE, 1, value) end
  end
  for gang = 1, 4 do
    local name = string.format("relayStatus%d", gang)
    if changed(preferences, old_preferences, name) then
      local value = POWER_ON_VALUES[preferences[name]]
      if value ~= nil then write_enum(device, MODE_CLUSTER, POWER_ON_ATTRIBUTE, gang, value) end
    end
  end
end

local function info_changed(_, device, _, args)
  local old_preferences = args and args.old_st_store and args.old_st_store.preferences or {}
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    update_parent_preferences(device, old_preferences)
    return
  end
  local gang = child_gang(device)
  local parent = parent_from_device(device)
  if gang == nil or parent == nil then return end
  local preferences = device.preferences or {}
  -- A profile update is asynchronous; initialize its button metadata when it arrives.
  initialize_button(device)
  local old_profile = args and args.old_st_store and args.old_st_store.profile
  local old_main = old_profile and old_profile.components and old_profile.components.main
  local old_switch = old_main and old_main.capabilities and old_main.capabilities.switch
  if old_main ~= nil and old_switch == nil and device:supports_capability(capabilities.switch) then
    -- A relay report may have arrived while the previous button profile was still active.
    parent:send(OnOff.attributes.OnOff:read(parent):to_endpoint(gang))
  end
  local mode = preferences.switchMode
  if changed(preferences, old_preferences, "switchMode")
      and (mode == "switch" or mode == "scene") then
    parent:set_field(mode_field(gang), mode, { persist = true })
    set_child_profile(device, mode)
    write_enum(parent, MODE_CLUSTER, MODE_ATTRIBUTE, gang, mode == "scene" and 1 or 0)
  end
  if changed(preferences, old_preferences, "countdownSeconds") then
    local seconds = tonumber(preferences.countdownSeconds)
    if seconds ~= nil and seconds == seconds then
      seconds = math.max(0, math.min(43200, math.floor(seconds)))
      parent:send(OnOff.server.commands.OnWithTimedOff(
        parent, data_types.Uint8(0), data_types.Uint16(seconds), data_types.Uint16(seconds)
      ):to_endpoint(gang))
      parent:set_field(string.format("countdown_gang_%d", gang), seconds, { persist = true })
    end
  end
end

return {
  NAME = "Zemismart KES606 Four Gang",
  supported_capabilities = { capabilities.refresh, capabilities.switch, capabilities.button },
  lifecycle_handlers = {
    added = initialize,
    init = initialize,
    doConfigure = do_configure,
    infoChanged = info_changed,
  },
  capability_handlers = {
    [capabilities.refresh.ID] = { [capabilities.refresh.commands.refresh.NAME] = refresh },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = function(_, device)
        relay_command(device, true)
      end,
      [capabilities.switch.commands.off.NAME] = function(_, device)
        relay_command(device, false)
      end,
    },
  },
  zigbee_handlers = {
    attr = {
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = onoff_report,
        [LIGHT_ATTRIBUTE] = light_report,
        [GLOBAL_POWER_ON_ATTRIBUTE] = global_power_on_report,
      },
      [MODE_CLUSTER] = {
        [MODE_ATTRIBUTE] = mode_report,
        [POWER_ON_ATTRIBUTE] = power_on_report,
      },
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
