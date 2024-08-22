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

local capabilities = require "st.capabilities"
local log = require "log"
local clusters = require "st.matter.clusters"
local MatterDriver = require "st.matter.driver"
local lua_socket = require "socket"
local utils = require "st.utils"
local device_lib = require "st.device"

local MOST_RECENT_TEMP = "mostRecentTemp"
local RECEIVED_X = "receivedX"
local RECEIVED_Y = "receivedY"
local HUESAT_SUPPORT = "huesatSupport"
local MIRED_KELVIN_CONVERSION_CONSTANT = 1000000
-- These values are a "sanity check" to check that values we are getting are reasonable
local COLOR_TEMPERATURE_KELVIN_MAX = 15000
local COLOR_TEMPERATURE_KELVIN_MIN = 1000
local COLOR_TEMPERATURE_MIRED_MAX = MIRED_KELVIN_CONVERSION_CONSTANT/COLOR_TEMPERATURE_KELVIN_MIN
local COLOR_TEMPERATURE_MIRED_MIN = MIRED_KELVIN_CONVERSION_CONSTANT/COLOR_TEMPERATURE_KELVIN_MAX
local SWITCH_LEVEL_LIGHTING_MIN = 1
local CURRENT_HUESAT_ATTR_MIN = 0
local CURRENT_HUESAT_ATTR_MAX = 254

local SWITCH_INITIALIZED = "__switch_intialized"
-- COMPONENT_TO_ENDPOINT_MAP is here only to preserve the endpoint mapping for
-- devices that were joined to this driver as MCD devices before the transition
-- to join all matter-switch devices as parent-child. This value will only exist
-- in the device table for devices that joined prior to this transition, and it
-- will not be set for new devices.
local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
-- COMPONENT_TO_ENDPOINT_MAP_BUTTON is for devices with button endpoints, to
-- preserve the MCD functionality for button devices from the matter-button
-- driver after it was merged into the matter-switch driver. Note that devices
-- containing both button endpoints and switch endpoints will use this field
-- rather than COMPONENT_TO_ENDPOINT_MAP.
local COMPONENT_TO_ENDPOINT_MAP_BUTTON = "__component_to_endpoint_map_button"
local IS_PARENT_CHILD_DEVICE = "__is_parent_child_device"
local COLOR_TEMP_BOUND_RECEIVED = "__colorTemp_bound_received"
local COLOR_TEMP_MIN = "__color_temp_min"
local COLOR_TEMP_MAX = "__color_temp_max"
local LEVEL_BOUND_RECEIVED = "__level_bound_received"
local LEVEL_MIN = "__level_min"
local LEVEL_MAX = "__level_max"
local AGGREGATOR_DEVICE_TYPE_ID = 0x000E
local ON_OFF_LIGHT_DEVICE_TYPE_ID = 0x0100
local DIMMABLE_LIGHT_DEVICE_TYPE_ID = 0x0101
local COLOR_TEMP_LIGHT_DEVICE_TYPE_ID = 0x010C
local EXTENDED_COLOR_LIGHT_DEVICE_TYPE_ID = 0x010D
local ON_OFF_PLUG_DEVICE_TYPE_ID = 0x010A
local DIMMABLE_PLUG_DEVICE_TYPE_ID = 0x010B
local ON_OFF_SWITCH_ID = 0x0103
local ON_OFF_DIMMER_SWITCH_ID = 0x0104
local ON_OFF_COLOR_DIMMER_SWITCH_ID = 0x0105
local GENERIC_SWITCH_ID = 0x000F
local device_type_profile_map = {
  [ON_OFF_LIGHT_DEVICE_TYPE_ID] = "light-binary",
  [DIMMABLE_LIGHT_DEVICE_TYPE_ID] = "light-level",
  [COLOR_TEMP_LIGHT_DEVICE_TYPE_ID] = "light-level-colorTemperature",
  [EXTENDED_COLOR_LIGHT_DEVICE_TYPE_ID] = "light-color-level",
  [ON_OFF_PLUG_DEVICE_TYPE_ID] = "plug-binary",
  [DIMMABLE_PLUG_DEVICE_TYPE_ID] = "plug-level",
  [ON_OFF_SWITCH_ID] = "switch-binary",
  [ON_OFF_DIMMER_SWITCH_ID] = "switch-level",
  [ON_OFF_COLOR_DIMMER_SWITCH_ID] = "switch-color-level",
  [GENERIC_SWITCH_ID] = "button"
}

local child_device_profile_overrides = {
  { vendor_id = 0x1321, product_id = 0x000D,  child_profile = "switch-binary" },
}

local detect_matter_thing

local START_BUTTON_PRESS = "__start_button_press"
local TIMEOUT_THRESHOLD = 10 --arbitrary timeout
local HELD_THRESHOLD = 1
-- this is the number of buttons for which we have a static profile already made
local STATIC_PROFILE_SUPPORTED = {2, 3, 4, 5, 6, 7, 8}

local DEFERRED_CONFIGURE = "__DEFERRED_CONFIGURE"

-- Some switches will send a MultiPressComplete event as part of a long press sequence. Normally the driver will create a
-- button capability event on receipt of MultiPressComplete, but in this case that would result in an extra event because
-- the "held" capability event is generated when the LongPress event is received. The IGNORE_NEXT_MPC flag is used
-- to tell the driver to ignore MultiPressComplete if it is received after a long press to avoid this extra event.
local IGNORE_NEXT_MPC = "__ignore_next_mpc"

-- These are essentially storing the supported features of a given endpoint
-- TODO: add an is_feature_supported_for_endpoint function to matter.device that takes an endpoint
local EMULATE_HELD = "__emulate_held" -- for non-MSR (MomentarySwitchRelease) devices we can emulate this on the software side
local SUPPORTS_MULTI_PRESS = "__multi_button" -- for MSM devices (MomentarySwitchMultiPress), create an event on receipt of MultiPressComplete
local INITIAL_PRESS_ONLY = "__initial_press_only" -- for devices that support MS (MomentarySwitch), but not MSR (MomentarySwitchRelease)

local HUE_MANUFACTURER_ID = 0x100B

--helper function to create list of multi press values
local function create_multi_list(size, supportsHeld)
  local list = {"pushed", "double"}
  if supportsHeld then table.insert(list, "held") end
  for i=3, size do
    table.insert(list, string.format("pushed_%dx", i))
  end
  return list
end

local function tbl_contains(array, value)
  for _, element in ipairs(array) do
    if element == value then
      return true
    end
  end
  return false
end

local function get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

local function set_field_for_endpoint(device, field, endpoint, value, additional_params)
  device:set_field(string.format("%s_%d", field, endpoint), value, additional_params)
end

local function init_press(device, endpoint)
  set_field_for_endpoint(device, START_BUTTON_PRESS, endpoint, lua_socket.gettime(), {persist = false})
end

local function emulate_held_event(device, ep)
  local now = lua_socket.gettime()
  local press_init = get_field_for_endpoint(device, START_BUTTON_PRESS, ep) or now -- if we don't have an init time, assume instant release
  if (now - press_init) < TIMEOUT_THRESHOLD then
    if (now - press_init) > HELD_THRESHOLD then
      device:emit_event_for_endpoint(ep, capabilities.button.button.held({state_change = true}))
    else
      device:emit_event_for_endpoint(ep, capabilities.button.button.pushed({state_change = true}))
    end
  end
  set_field_for_endpoint(device, START_BUTTON_PRESS, ep, nil, {persist = false})
end

local function convert_huesat_st_to_matter(val)
  return utils.clamp_value(math.floor((val * 0xFE) / 100.0 + 0.5), CURRENT_HUESAT_ATTR_MIN, CURRENT_HUESAT_ATTR_MAX)
end

local function mired_to_kelvin(value)
  if value == 0 then -- shouldn't happen, but has
    value = 1
    log.warn(string.format("Received a color temperature of 0 mireds. Using a color temperature of 1 mired to avoid divide by zero"))
  end
  -- we divide inside the rounding and multiply outside of it because we expect these
  -- bounds to be multiples of 100
  return utils.round((MIRED_KELVIN_CONVERSION_CONSTANT / value) / 100) * 100
end

--- component_to_endpoint helper function to handle situations where
--- device does not have endpoint ids in sequential order from 1
--- In this case the function returns the lowest endpoint value that isn't 0
--- and supports the OnOff cluster. This is done to bypass the
--- BRIDGED_NODE_DEVICE_TYPE on bridged devices
local function find_default_endpoint(device, component)
  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.Feature.MOMENTARY_SWITCH})
  local all_eps = {}

  for _,v in ipairs(switch_eps) do
    table.insert(all_eps, v)
  end
  for _,v in ipairs(button_eps) do
    table.insert(all_eps, v)
  end
  table.sort(all_eps)

  for _, v in ipairs(all_eps) do
    if v ~= 0 then --0 is the matter RootNode endpoint
      return v
    end
  end
  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return device.MATTER_DEFAULT_ENDPOINT
end

local function assign_child_profile(device, child_ep)
  local profile

  -- check if device has an overriden child profile that differs from the profile
  -- that would match the child's device type
  for _, fingerprint in ipairs(child_device_profile_overrides) do
    if device.manufacturer_info.vendor_id == fingerprint.vendor_id and
       device.manufacturer_info.product_id == fingerprint.product_id then
      return fingerprint.child_profile
    end
  end

  for _, ep in ipairs(device.endpoints) do
    if ep.endpoint_id == child_ep then
      -- Some devices report multiple device types which are a subset of
      -- a superset device type (For example, Dimmable Light is a superset of
      -- On/Off light). This mostly applies to the four light types, so we will want
      -- to match the profile for the superset device type. This can be done by
      -- matching to the device type with the highest ID
      local id = 0
      for _, dt in ipairs(ep.device_types) do
        id = math.max(id, dt.device_type_id)
      end
      profile = device_type_profile_map[id]
    end
  end
  -- default to "switch-binary" if no profile is found
  return profile or "switch-binary"
end

local function configure_buttons(device)
  if device.network_type ~= device_lib.NETWORK_TYPE_CHILD then
    local MS = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.Feature.MOMENTARY_SWITCH})
    local MSR = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.Feature.MOMENTARY_SWITCH_RELEASE})
    device.log.debug(#MSR.." momentary switch release endpoints")
    local MSL = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.Feature.MOMENTARY_SWITCH_LONG_PRESS})
    device.log.debug(#MSL.." momentary switch long press endpoints")
    local MSM = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.Feature.MOMENTARY_SWITCH_MULTI_PRESS})
    device.log.debug(#MSM.." momentary switch multi press endpoints")
    for _, ep in ipairs(MS) do
      local supportedButtonValues_event = capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})
      -- this ordering is important, as MSL & MSM devices must also support MSR
      if tbl_contains(MSM, ep) then
        -- ask the device to tell us its max number of presses
        device.log.debug("sending multi press max read")
        device:send(clusters.Switch.attributes.MultiPressMax:read(device, ep))
        set_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ep, true, {persist = true})
        supportedButtonValues_event = nil -- deferred until max press handler
      elseif tbl_contains(MSL, ep) then
        device.log.debug("configuring for long press device")
      elseif tbl_contains(MSR, ep) then
        device.log.debug("configuring for emulated held")
        set_field_for_endpoint(device, EMULATE_HELD, ep, true, {persist = true})
      else -- device only supports momentary switch, no release events
        device.log.debug("configuring for press event only")
        supportedButtonValues_event = capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})
        set_field_for_endpoint(device, INITIAL_PRESS_ONLY, ep, true, {persist = true})
      end

      if supportedButtonValues_event then
        device:emit_event_for_endpoint(ep, supportedButtonValues_event)
      end
      device:emit_event_for_endpoint(ep, capabilities.button.button.pushed({state_change = false}))
    end
  end
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%d", ep_id))
end

local function initialize_switch(driver, device)
  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.Feature.MOMENTARY_SWITCH})
  local all_eps = {}

  local new_profile = nil

  local component_map = {}
  local current_component_number = 2
  local component_map_used = false
  local parent_child_device = false

  if #switch_eps > 0 or #button_eps > 0 then
    for _,v in ipairs(switch_eps) do
      table.insert(all_eps, v)
    end
    for _,v in ipairs(button_eps) do
      table.insert(all_eps, v)
    end
    table.sort(all_eps)
    -- Since we do not support bindings at the moment, we only want to count clusters
    -- that have been implemented as server. This can be removed when we have
    -- support for bindings.
    local num_switch_server_eps = 0
    local num_button_server_eps = 0
    local main_endpoint = find_default_endpoint(device)

    for _, ep in ipairs(all_eps) do
      if device:supports_server_cluster(clusters.Switch.ID, ep) then
        -- Configure MCD for button endpoints
        if tbl_contains(STATIC_PROFILE_SUPPORTED, #button_eps) then
          if ep ~= main_endpoint then
            component_map[string.format("button%d", current_component_number)] = ep
            current_component_number = current_component_number + 1
          else
            component_map["main"] = ep
          end
          component_map_used = true
        end
      elseif device:supports_server_cluster(clusters.OnOff.ID, ep) then
        -- Create child devices for non-main switch endpoints
        num_switch_server_eps = num_switch_server_eps + 1
        if ep ~= main_endpoint then -- don't create a child device that maps to the main endpoint
          local name = string.format("%s %d", device.label, num_switch_server_eps)
          local child_profile = assign_child_profile(device, ep)
          driver:try_create_device(
              {
                type = "EDGE_CHILD",
                label = name,
                profile = child_profile,
                parent_device_id = device.id,
                parent_assigned_child_key = string.format("%d", ep),
                vendor_provided_label = name
              }
          )
          current_component_number = current_component_number + 1
          parent_child_device = true
        end
      end
    end

    if parent_child_device then
      -- If the device is a parent child device, then set the find_child function on init.
      -- This is persisted because initialize switch is only run once, but find_child function should be set
      -- on each driver init.
      device:set_field(IS_PARENT_CHILD_DEVICE, true, {persist = true})
    end

    device:set_field(SWITCH_INITIALIZED, true)

    if #button_eps > 0 then
      local battery_support = false
      if device.manufacturer_info.vendor_id ~= HUE_MANUFACTURER_ID and
          #device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.Feature.BATTERY}) > 0 then
        battery_support = true
      end
      if tbl_contains(STATIC_PROFILE_SUPPORTED, #button_eps) then
        if battery_support then
          new_profile = string.format("%d-button-battery", #button_eps)
        else
          new_profile = string.format("%d-button", #button_eps)
        end
      elseif not battery_support then
        -- a battery-less button/remote (either single or will use parent/child)
        new_profile = "button"
      end

      if new_profile then
        device:try_update_metadata({profile = new_profile})
      end
    else
      -- The case where num_switch_server_eps > 0 is a workaround for devices that have a
      -- Light Switch device type but implement the On Off cluster as server (which is against the spec
      -- for this device type). By default, we do not support Light Switch device types because by spec these
      -- devices need bindings to work correctly (On/Off cluster is client in this case), so these device types
      -- do not have a generic fingerprint and will join as a matter-thing. However, we have seen some devices
      -- claim to be Light Switch device types and still implement their clusters as server, so this is a
      -- workaround for those devices.
      if num_switch_server_eps > 0 and detect_matter_thing(device) == true then
        local id = 0
        for _, ep in ipairs(device.endpoints) do
          -- main_endpoint only supports server cluster by definition of get_endpoints()
          if main_endpoint == ep.endpoint_id then
            for _, dt in ipairs(ep.device_types) do
              -- no device type that is not in the switch subset should be considered.
              if (ON_OFF_SWITCH_ID <= dt.device_type_id and dt.device_type_id <= ON_OFF_COLOR_DIMMER_SWITCH_ID) then
                id = math.max(id, dt.device_type_id)
              end
            end
            break
          end
        end

        if device_type_profile_map[id] ~= nil then
          device:try_update_metadata({profile = device_type_profile_map[id]})
        end
      end
    end
  end
  if device:get_field(IS_PARENT_CHILD_DEVICE) == true then
    device:set_find_child(find_child)
  end

  if component_map_used then
    device:set_field(COMPONENT_TO_ENDPOINT_MAP_BUTTON, component_map, {persist = true})
  end

  if #button_eps > 0 then
    if new_profile then
      device:set_field(DEFERRED_CONFIGURE, true)
    else
      configure_buttons(device)
    end
  end
end

local function component_to_endpoint(device, component)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP_BUTTON) or device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  if map[component] then
    return map[component]
  end
  return find_default_endpoint(device, component)
end

local function endpoint_to_component(device, ep)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP_BUTTON) or device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  for component, endpoint in pairs(map) do
    if endpoint == ep then
      return component
    end
  end
  return "main"
end

local function detect_bridge(device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == AGGREGATOR_DEVICE_TYPE_ID then
        return true
      end
    end
  end
  return false
end

local function device_init(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then
    device:set_component_to_endpoint_fn(component_to_endpoint)
    device:set_endpoint_to_component_fn(endpoint_to_component)
    -- initialize_switch will create parent-child devices as needed for multi-switch devices.
    -- However, we want to maintain support for existing MCD devices, so do not initialize
    -- device if it has already been previously initialized as an MCD device.
    -- Also, do not attempt a profile switch for a bridge device.
    if not device:get_field(COMPONENT_TO_ENDPOINT_MAP) and
       not device:get_field(SWITCH_INITIALIZED) and
       not detect_bridge(device) then
      -- create child devices as needed for multi-switch devices
      initialize_switch(driver, device)
    end
    if device:get_field(IS_PARENT_CHILD_DEVICE) == true then
      device:set_find_child(find_child)
    end
    device:subscribe()
  end
end

local function device_removed(driver, device)
  log.info("device removed")
end

local function handle_switch_on(driver, device, cmd)
  if type(device.register_native_capability_cmd_handler) == "function" then
    device:register_native_capability_cmd_handler(cmd.capability, cmd.command)
  end
  local endpoint_id = device:component_to_endpoint(cmd.component)
  --TODO use OnWithRecallGlobalScene for devices with the LT feature
  local req = clusters.OnOff.server.commands.On(device, endpoint_id)
  device:send(req)
end

local function handle_switch_off(driver, device, cmd)
  if type(device.register_native_capability_cmd_handler) == "function" then
    device:register_native_capability_cmd_handler(cmd.capability, cmd.command)
  end
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.Off(device, endpoint_id)
  device:send(req)
end

local function handle_set_level(driver, device, cmd)
  if type(device.register_native_capability_cmd_handler) == "function" then
    device:register_native_capability_cmd_handler(cmd.capability, cmd.command)
  end
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local level = math.floor(cmd.args.level/100.0 * 254)
  local req = clusters.LevelControl.server.commands.MoveToLevelWithOnOff(device, endpoint_id, level, cmd.args.rate or 0, 0 ,0)
  device:send(req)
end

local TRANSITION_TIME = 0 --1/10ths of a second
-- When sent with a command, these options mask and override bitmaps cause the command
-- to take effect when the switch/light is off.
local OPTIONS_MASK = 0x01
local OPTIONS_OVERRIDE = 0x01

local function handle_set_color(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req
  local huesat_endpoints = device:get_endpoints(clusters.ColorControl.ID, {feature_bitmap = clusters.ColorControl.FeatureMap.HUE_AND_SATURATION})
  if tbl_contains(huesat_endpoints, endpoint_id) then
    local hue = convert_huesat_st_to_matter(cmd.args.color.hue)
    local sat = convert_huesat_st_to_matter(cmd.args.color.saturation)
    req = clusters.ColorControl.server.commands.MoveToHueAndSaturation(device, endpoint_id, hue, sat, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
  else
    local x, y, _ = utils.safe_hsv_to_xy(cmd.args.color.hue, cmd.args.color.saturation)
    req = clusters.ColorControl.server.commands.MoveToColor(device, endpoint_id, x, y, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
  end
  device:send(req)
end

local function handle_set_hue(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local huesat_endpoints = device:get_endpoints(clusters.ColorControl.ID, {feature_bitmap = clusters.ColorControl.FeatureMap.HUE_AND_SATURATION})
  if tbl_contains(huesat_endpoints, endpoint_id) then
    local hue = convert_huesat_st_to_matter(cmd.args.hue)
    local req = clusters.ColorControl.server.commands.MoveToHue(device, endpoint_id, hue, 0, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
    device:send(req)
  else
    log.warn("Device does not support huesat features on its color control cluster")
  end
end

local function handle_set_saturation(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local huesat_endpoints = device:get_endpoints(clusters.ColorControl.ID, {feature_bitmap = clusters.ColorControl.FeatureMap.HUE_AND_SATURATION})
  if tbl_contains(huesat_endpoints, endpoint_id) then
    local sat = convert_huesat_st_to_matter(cmd.args.saturation)
    local req = clusters.ColorControl.server.commands.MoveToSaturation(device, endpoint_id, sat, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
    device:send(req)
  else
    log.warn("Device does not support huesat features on its color control cluster")
  end
end

local function handle_set_color_temperature(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local temp_in_mired = utils.round(MIRED_KELVIN_CONVERSION_CONSTANT/cmd.args.temperature)
  local req = clusters.ColorControl.server.commands.MoveToColorTemperature(device, endpoint_id, temp_in_mired, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
  device:set_field(MOST_RECENT_TEMP, cmd.args.temperature)
  device:send(req)
end

local function handle_refresh(driver, device, cmd)
  --Note: no endpoint specified indicates a wildcard endpoint
  local req = clusters.OnOff.attributes.OnOff:read(device)
  device:send(req)
end

-- Fallback handler for responses that dont have their own handler
local function matter_handler(driver, device, response_block)
  log.info(string.format("Fallback handler for %s", response_block))
end

local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  end
end

local function level_attr_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    local level = math.floor((ib.data.value / 254.0 * 100) + 0.5)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switchLevel.level(level))
  end
end

local function hue_attr_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    local hue = math.floor((ib.data.value / 0xFE * 100) + 0.5)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.hue(hue))
  end
end

local function sat_attr_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    local sat = math.floor((ib.data.value / 0xFE * 100) + 0.5)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.saturation(sat))
  end
end

local function temp_attr_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    if (ib.data.value < COLOR_TEMPERATURE_MIRED_MIN or ib.data.value > COLOR_TEMPERATURE_MIRED_MAX) then
      device.log.warn_with({hub_logs = true}, string.format("Device reported color temperature %d mired outside of sane range of %.2f-%.2f", ib.data.value, COLOR_TEMPERATURE_MIRED_MIN, COLOR_TEMPERATURE_MIRED_MAX))
      return
    end
    local temp = utils.round(MIRED_KELVIN_CONVERSION_CONSTANT/ib.data.value)
    local temp_device = device
    if device:get_field(IS_PARENT_CHILD_DEVICE) == true then
      temp_device = find_child(device, ib.endpoint_id) or device
    end
    local most_recent_temp = temp_device:get_field(MOST_RECENT_TEMP)
    -- this is to avoid rounding errors from the round-trip conversion of Kelvin to mireds
    if most_recent_temp ~= nil and
      most_recent_temp <= utils.round(MIRED_KELVIN_CONVERSION_CONSTANT/(ib.data.value - 1)) and
      most_recent_temp >= utils.round(MIRED_KELVIN_CONVERSION_CONSTANT/(ib.data.value + 1)) then
        temp = most_recent_temp
    end
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorTemperature.colorTemperature(temp))
  end
end

local mired_bounds_handler_factory = function(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    if (ib.data.value < COLOR_TEMPERATURE_MIRED_MIN or ib.data.value > COLOR_TEMPERATURE_MIRED_MAX) then
      device.log.warn_with({hub_logs = true}, string.format("Device reported a color temperature %d mired outside of sane range of %.2f-%.2f", ib.data.value, COLOR_TEMPERATURE_MIRED_MIN, COLOR_TEMPERATURE_MIRED_MAX))
      return
    end
    local temp_in_kelvin = mired_to_kelvin(ib.data.value)
    set_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED..minOrMax, ib.endpoint_id, temp_in_kelvin)
    local min = get_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED..COLOR_TEMP_MIN, ib.endpoint_id)
    local max = get_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED..COLOR_TEMP_MAX, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = min, maximum = max} }))
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min color temperature %d K that is not lower than the reported max color temperature %d K", min, max))
      end
      set_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED..COLOR_TEMP_MAX, ib.endpoint_id, nil)
      set_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED..COLOR_TEMP_MIN, ib.endpoint_id, nil)
    end
  end
end

local level_bounds_handler_factory = function(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local lighting_endpoints = device:get_endpoints(clusters.LevelControl.ID, {feature_bitmap = clusters.LevelControl.FeatureMap.LIGHTING})
    local lighting_support = tbl_contains(lighting_endpoints, ib.endpoint_id)
    -- If the lighting feature is supported then we should check if the reported level is at least 1.
    if lighting_support and ib.data.value < SWITCH_LEVEL_LIGHTING_MIN then
      device.log.warn_with({hub_logs = true}, string.format("Lighting device reported a switch level %d outside of supported capability range", ib.data.value))
      return
    end
    -- Convert level from given range of 0-254 to range of 0-100.
    local level = utils.round(ib.data.value / 254.0 * 100)
    -- If the device supports the lighting feature, the minimum capability level should be 1 so we do not send a 0 value for the level attribute
    if lighting_support and level == 0 then
      level = 1
    end
    set_field_for_endpoint(device, LEVEL_BOUND_RECEIVED..minOrMax, ib.endpoint_id, level)
    local min = get_field_for_endpoint(device, LEVEL_BOUND_RECEIVED..LEVEL_MIN, ib.endpoint_id)
    local max = get_field_for_endpoint(device, LEVEL_BOUND_RECEIVED..LEVEL_MAX, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switchLevel.levelRange({ value = {minimum = min, maximum = max} }))
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min level value %d that is not lower than the reported max level value %d", min, max))
      end
      set_field_for_endpoint(device, LEVEL_BOUND_RECEIVED..LEVEL_MAX, ib.endpoint_id, nil)
      set_field_for_endpoint(device, LEVEL_BOUND_RECEIVED..LEVEL_MIN, ib.endpoint_id, nil)
    end
  end
end

local color_utils = require "color_utils"

local function x_attr_handler(driver, device, ib, response)
  local y = device:get_field(RECEIVED_Y)
  --TODO it is likely that both x and y attributes are in the response (not guaranteed though)
  -- if they are we can avoid setting fields on the device.
  if y == nil then
    device:set_field(RECEIVED_X, ib.data.value)
  else
    local x = ib.data.value
    local h, s, _ = color_utils.safe_xy_to_hsv(x, y)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.hue(h))
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.saturation(s))
    device:set_field(RECEIVED_Y, nil)
  end
end

local function y_attr_handler(driver, device, ib, response)
  local x = device:get_field(RECEIVED_X)
  if x == nil then
    device:set_field(RECEIVED_Y, ib.data.value)
  else
    local y = ib.data.value
    local h, s, _ = color_utils.safe_xy_to_hsv(x, y)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.hue(h))
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.saturation(s))
    device:set_field(RECEIVED_X, nil)
  end
end

--TODO setup configure handler to read this attribute.
local function color_cap_attr_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    if ib.data.value & 0x1 then
      device:set_field(HUESAT_SUPPORT, true)
    end
  end
end

local function illuminance_attr_handler(driver, device, ib, response)
  local lux = math.floor(10 ^ ((ib.data.value - 1) / 10000))
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.illuminanceMeasurement.illuminance(lux))
end

local function occupancy_attr_handler(driver, device, ib, response)
  device:emit_event(ib.data.value == 0x01 and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
end

local function initial_press_event_handler(driver, device, ib, response)
  if get_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
    -- Receipt of an InitialPress event means we do not want to ignore the next MultiPressComplete event
    -- or else we would potentially not create the expected button capability event
    set_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id, nil)
  else
    if get_field_for_endpoint(device, INITIAL_PRESS_ONLY, ib.endpoint_id) then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.pushed({state_change = true}))
    elseif get_field_for_endpoint(device, EMULATE_HELD, ib.endpoint_id) then
      -- if our button doesn't differentiate between short and long holds, do it in code by keeping track of the press down time
      init_press(device, ib.endpoint_id)
    end
  end
end

-- if the device distinguishes a long press event, it will always be a "held"
-- there's also a "long release" event, but this event is required to come first
local function long_press_event_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.held({state_change = true}))
  if get_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
    -- Ignore the next MultiPressComplete event if it is sent as part of this "long press" event sequence
    set_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id, true)
  end
end

local function short_release_event_handler(driver, device, ib, response)
  if not get_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
    if get_field_for_endpoint(device, EMULATE_HELD, ib.endpoint_id) then
      emulate_held_event(device, ib.endpoint_id)
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.pushed({state_change = true}))
    end
  end
end

local function multi_press_complete_event_handler(driver, device, ib, response)
  -- in the case of multiple button presses
  -- emit number of times, multiple presses have been completed
  if ib.data and get_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id) ~= true then
    local press_value = ib.data.elements.total_number_of_presses_counted.value
    --capability only supports up to 6 presses
    if press_value < 7 then
      local button_event = capabilities.button.button.pushed({state_change = true})
      if press_value == 2 then
        button_event = capabilities.button.button.double({state_change = true})
      elseif press_value > 2 then
        button_event = capabilities.button.button(string.format("pushed_%dx", press_value), {state_change = true})
      end

      device:emit_event_for_endpoint(ib.endpoint_id, button_event)
    else
      log.info(string.format("Number of presses (%d) not supported by capability", press_value))
    end
  end
  set_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id, nil)
end

local function battery_percent_remaining_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

local function max_press_handler(driver, device, ib, response)
  local max = ib.data.value or 1 --get max number of presses
  device.log.debug("Device supports "..max.." presses")
  -- capability only supports up to 6 presses
  if max > 6 then
    log.info("Device supports more than 6 presses")
    max = 6
  end
  local MSL = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.Feature.MOMENTARY_SWITCH_LONG_PRESS})
  local supportsHeld = tbl_contains(MSL, ib.endpoint_id)
  local values = create_multi_list(max, supportsHeld)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.supportedButtonValues(values, {visibility = {displayed = false}}))
end

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    device:subscribe()
    if device:get_field(DEFERRED_CONFIGURE) and device.network_type ~= device_lib.NETWORK_TYPE_CHILD then
      -- profile has changed, and we deferred setting up our buttons, so do that now
      configure_buttons(device)
      device:set_field(DEFERRED_CONFIGURE, nil)
    end
  end
end

local function device_added(driver, device)
  -- refresh child devices to get initial attribute state in case child device
  -- was created after the initial subscription report
  if device.network_type == device_lib.NETWORK_TYPE_CHILD then
    handle_refresh(driver, device)
  end

  -- call device init in case init is not called after added due to device caching
  device_init(driver, device)
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    removed = device_removed,
    infoChanged = info_changed
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.LevelControl.ID] = {
        [clusters.LevelControl.attributes.CurrentLevel.ID] = level_attr_handler,
        [clusters.LevelControl.attributes.MaxLevel.ID] = level_bounds_handler_factory(LEVEL_MAX),
        [clusters.LevelControl.attributes.MinLevel.ID] = level_bounds_handler_factory(LEVEL_MIN),
      },
      [clusters.ColorControl.ID] = {
        [clusters.ColorControl.attributes.CurrentHue.ID] = hue_attr_handler,
        [clusters.ColorControl.attributes.CurrentSaturation.ID] = sat_attr_handler,
        [clusters.ColorControl.attributes.ColorTemperatureMireds.ID] = temp_attr_handler,
        [clusters.ColorControl.attributes.CurrentX.ID] = x_attr_handler,
        [clusters.ColorControl.attributes.CurrentY.ID] = y_attr_handler,
        [clusters.ColorControl.attributes.ColorCapabilities.ID] = color_cap_attr_handler,
        [clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds.ID] = mired_bounds_handler_factory(COLOR_TEMP_MIN), -- max mireds = min kelvin
        [clusters.ColorControl.attributes.ColorTempPhysicalMinMireds.ID] = mired_bounds_handler_factory(COLOR_TEMP_MAX), -- min mireds = max kelvin
      },
      [clusters.IlluminanceMeasurement.ID] = {
        [clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID] = illuminance_attr_handler
      },
      [clusters.OccupancySensing.ID] = {
        [clusters.OccupancySensing.attributes.Occupancy.ID] = occupancy_attr_handler,
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = battery_percent_remaining_attr_handler,
      },
      [clusters.Switch.ID] = {
        [clusters.Switch.attributes.MultiPressMax.ID] = max_press_handler
      }
    },
    event = {
      [clusters.Switch.ID] = {
        [clusters.Switch.events.InitialPress.ID] = initial_press_event_handler,
        [clusters.Switch.events.LongPress.ID] = long_press_event_handler,
        [clusters.Switch.events.ShortRelease.ID] = short_release_event_handler,
        [clusters.Switch.events.MultiPressComplete.ID] = multi_press_complete_event_handler
      }
    },
    fallback = matter_handler,
  },
  subscribed_attributes = {
    [capabilities.switch.ID] = {
      clusters.OnOff.attributes.OnOff
    },
    [capabilities.switchLevel.ID] = {
      clusters.LevelControl.attributes.CurrentLevel,
      clusters.LevelControl.attributes.MaxLevel,
      clusters.LevelControl.attributes.MinLevel,
    },
    [capabilities.colorControl.ID] = {
      clusters.ColorControl.attributes.CurrentHue,
      clusters.ColorControl.attributes.CurrentSaturation,
      clusters.ColorControl.attributes.CurrentX,
      clusters.ColorControl.attributes.CurrentY,
    },
    [capabilities.colorTemperature.ID] = {
      clusters.ColorControl.attributes.ColorTemperatureMireds,
      clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
      clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
    },
    [capabilities.illuminanceMeasurement.ID] = {
      clusters.IlluminanceMeasurement.attributes.MeasuredValue
    },
    [capabilities.motionSensor.ID] = {
      clusters.OccupancySensing.attributes.Occupancy
    },
    [capabilities.battery.ID] = {
      clusters.PowerSource.attributes.BatPercentRemaining,
    },
  },
  subscribed_events = {
    [capabilities.button.ID] = {
      clusters.Switch.events.InitialPress,
      clusters.Switch.events.LongPress,
      clusters.Switch.events.ShortRelease,
      clusters.Switch.events.MultiPressComplete,
    },
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = handle_set_level
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = handle_refresh,
    },
    [capabilities.colorControl.ID] = {
      [capabilities.colorControl.commands.setColor.NAME] = handle_set_color,
      [capabilities.colorControl.commands.setHue.NAME] = handle_set_hue,
      [capabilities.colorControl.commands.setSaturation.NAME] = handle_set_saturation,
    },
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = handle_set_color_temperature,
    },
  },
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.colorControl,
    capabilities.colorTemperature,
    capabilities.motionSensor,
    capabilities.illuminanceMeasurement,
    capabilities.button,
    capabilities.battery
  },
  sub_drivers = {
    require("eve-energy"),
  }
}

function detect_matter_thing(device)
  for _, capability in ipairs(matter_driver_template.supported_capabilities) do
    if device:supports_capability(capability) then
      return false
    end
  end
  return device:supports_capability(capabilities.refresh)
end

local matter_driver = MatterDriver("matter-switch", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
