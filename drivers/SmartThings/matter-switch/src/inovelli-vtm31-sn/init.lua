-- Copyright 2025 SmartThings
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

local clusters = require "st.matter.clusters"
local configure_buttons = require "configure-buttons"
local data_types = require "st.matter.data_types"
local device_lib = require "st.device"
local log = require "log"
local version = require "version"

-- Include driver-side definitions when lua libs api version is < 10
if version.api < 10 then
  clusters.ModeSelect = require "ModeSelect"
end

local INOVELLI_VTM31_SN_FINGERPRINT = { vendor_id = 0x1361, product_id = 0x0001 }
local LATEST_CLOCK_SET_TIMESTAMP = "latest_clock_set_timestamp"

local SWITCH_INITIALIZED = "__switch_intialized"
local COMPONENT_TO_ENDPOINT_MAP_BUTTON = "__component_to_endpoint_map_button"
local IS_PARENT_CHILD_DEVICE = "__is_parent_child_device"
local BUTTON_DEVICE_PROFILED = "__button_device_profiled"

local DIMMABLE_LIGHT_DEVICE_TYPE_ID = 0x0101
local EXTENDED_COLOR_LIGHT_DEVICE_TYPE_ID = 0x010D
local ON_OFF_DIMMER_SWITCH_ID = 0x0104
local GENERIC_SWITCH_ID = 0x000F

local device_type_attribute_map = {
  [DIMMABLE_LIGHT_DEVICE_TYPE_ID] = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel
  },
  [EXTENDED_COLOR_LIGHT_DEVICE_TYPE_ID] = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel,
    clusters.ColorControl.attributes.ColorTemperatureMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
    clusters.ColorControl.attributes.CurrentHue,
    clusters.ColorControl.attributes.CurrentSaturation,
    clusters.ColorControl.attributes.CurrentX,
    clusters.ColorControl.attributes.CurrentY
  },
  [ON_OFF_DIMMER_SWITCH_ID] = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel
  },
  [GENERIC_SWITCH_ID] = {
    clusters.PowerSource.attributes.BatPercentRemaining,
    clusters.Switch.events.InitialPress,
    clusters.Switch.events.LongPress,
    clusters.Switch.events.ShortRelease,
    clusters.Switch.events.MultiPressComplete
  }
}

local preference_map_inovelli_vtm31sn = {
  switchMode = {parameter_number = 1, size = data_types.Uint8},
  smartBulbMode = {parameter_number = 2, size = data_types.Uint8},
  dimmingEdge = {parameter_number = 3, size = data_types.Uint8},
  dimmingSpeed = {parameter_number = 4, size = data_types.Uint8},
  relayClick = {parameter_number = 5, size = data_types.Uint8},
  ledIndicatorColor = {parameter_number = 6, size = data_types.Uint8},
}

local function is_inovelli_vtm31_sn(opts, driver, device)
  if not device.manufacturer_info then return false end
  if device.manufacturer_info.vendor_id == INOVELLI_VTM31_SN_FINGERPRINT.vendor_id and
     device.manufacturer_info.product_id == INOVELLI_VTM31_SN_FINGERPRINT.product_id then
     log.info("Using Inovelli VTM31 sub driver")
    return true
  end
  return false
end

local preferences_to_numeric_value = function(new_value)
  local numeric = tonumber(new_value)
  if numeric == nil then -- in case the value is Boolean
    numeric = new_value and 1 or 0
  end
  return numeric
end

local function get_first_non_zero_endpoint(endpoints)
  for _,ep in ipairs(endpoints) do
    if ep ~= 0 then -- 0 is the matter RootNode endpoint
      return ep
    end
  end
  return nil
end

local function find_default_endpoint(device)
  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  table.sort(switch_eps)
  local main_endpoint = get_first_non_zero_endpoint(switch_eps)
  if main_endpoint ~= nil then
    return main_endpoint
  end
  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return device.MATTER_DEFAULT_ENDPOINT
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%d", ep_id))
end

local function initialize_buttons_and_switches(driver, device, main_endpoint)
  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  table.sort(switch_eps)
  table.sort(button_eps)
  local component_map = {}
  local current_component_number = 1
  -- Since we do not support bindings at the moment, we only want to count clusters
  -- that have been implemented as server. This can be removed when we have
  -- support for bindings.
  local num_switch_server_eps = 0
  device:try_update_metadata({profile = "inovelli-vtm31-sn"})
  device:set_field(BUTTON_DEVICE_PROFILED, true)
  -- The first switch endpoint will be the main component and the three buttons
  -- will be added as additional components in a MCD profile.
  component_map["main"] = main_endpoint
  for _, ep in ipairs(button_eps) do
    component_map[string.format("button%d", current_component_number)] = ep
    current_component_number = current_component_number + 1
  end
  device:set_field(COMPONENT_TO_ENDPOINT_MAP_BUTTON, component_map, {persist = true})
  configure_buttons.configure_buttons(device)
  for _, ep in ipairs(switch_eps) do
    if device:supports_server_cluster(clusters.OnOff.ID, ep) then
      num_switch_server_eps = num_switch_server_eps + 1
      if ep ~= main_endpoint then -- don't create a child device that maps to the main endpoint
        local name = string.format("%s %d", device.label, num_switch_server_eps)
        driver:try_create_device(
          {
            type = "EDGE_CHILD",
            label = name,
            profile = "light-color-level",
            parent_device_id = device.id,
            parent_assigned_child_key = string.format("%d", ep),
            vendor_provided_label = name
          }
        )
      end
    end
  end
  -- Since this device is a parent child device, set the find_child function on init.
  -- This is persisted because initialize switch is only run once, but find_child function should be set
  -- on each driver init.
  device:set_field(IS_PARENT_CHILD_DEVICE, true, {persist = true})
  device:set_field(SWITCH_INITIALIZED, true)
end

local function component_to_endpoint(device, component)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP_BUTTON) or {}
  if map[component] then
    return map[component]
  end
  return find_default_endpoint(device)
end

local function endpoint_to_component(device, ep)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP_BUTTON) or {}
  for component, endpoint in pairs(map) do
    if endpoint == ep then
      return component
    end
  end
  return "main"
end

local function device_init(driver, device)
  if device.network_type ~= device_lib.NETWORK_TYPE_MATTER then
    return
  end
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  local main_endpoint = find_default_endpoint(device)
  if not device:get_field(SWITCH_INITIALIZED) then
    -- create child devices as needed for multi-switch devices
    initialize_buttons_and_switches(driver, device, main_endpoint)
  end
  if device:get_field(IS_PARENT_CHILD_DEVICE) == true then
    device:set_find_child(find_child)
  end
  -- ensure subscription to all endpoint attributes- including those mapped to child devices
  for _, ep in ipairs(device.endpoints) do
    if ep.endpoint_id ~= main_endpoint then
      local id = 0
      for _, dt in ipairs(ep.device_types) do
        id = math.max(id, dt.device_type_id)
      end
      for _, attr in pairs(device_type_attribute_map[id] or {}) do
        if id == GENERIC_SWITCH_ID and attr ~= clusters.PowerSource.attributes.BatPercentRemaining then
          device:add_subscribed_event(attr)
        else
          device:add_subscribed_attribute(attr)
        end
      end
    end
  end
  device:subscribe()
end

local function info_changed(driver, device, event, args)
  if device.network_type == device_lib.NETWORK_TYPE_CHILD then
    return
  end
  local time_diff = 3
  local last_clock_set_time = device:get_field(LATEST_CLOCK_SET_TIMESTAMP)
  if last_clock_set_time ~= nil then
    time_diff = os.difftime(os.time(), last_clock_set_time)
  end
  device:set_field(LATEST_CLOCK_SET_TIMESTAMP, os.time(), {persist = true})
  -- don't process preference updates more than once every 2 seconds
  if time_diff > 2 then
    local preferences = preference_map_inovelli_vtm31sn
    for id, value in pairs(device.preferences) do
      if args.old_st_store.preferences[id] ~= value and preferences and preferences[id] then
        local new_parameter_value
        if preferences[id].parameter_number == 4 then
          new_parameter_value = math.tointeger(device.preferences[id])
        else
          new_parameter_value = preferences_to_numeric_value(device.preferences[id])
        end
        local req = clusters.ModeSelect.server.commands.ChangeToMode(device, preferences[id].parameter_number, new_parameter_value)
        device:send(req)
      end
    end
  end
end

local inovelli_vtm31_sn_handler = {
  NAME = "inovelli vtm31-sn handler",
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed
  },
  matter_handlers = {
  },
  can_handle = is_inovelli_vtm31_sn
}

return inovelli_vtm31_sn_handler
