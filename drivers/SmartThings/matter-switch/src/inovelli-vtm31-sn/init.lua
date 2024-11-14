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

local cluster_base = require "st.matter.cluster_base"
local clusters = require "st.matter.clusters"
local buttons = require "buttons"
local data_types = require "st.matter.data_types"
local device_lib = require "st.device"
local log = require "log"
local utils = require "st.utils"

-------------------------------------------------------------------------------------
-- Inovelli VTM31-SN specifics
-------------------------------------------------------------------------------------

local INOVELLI_VTM31_SN_FINGERPRINT = { vendor_id = 0x1361, product_id = 0x0001 }

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
local LATEST_CLOCK_SET_TIMESTAMP = "__latest_clock_set_timestamp"

local PRIVATE_CLUSTER_ATTR_ID = 0x122F0000
local PRIVATE_CLUSTER_ENDPOINT_ID = 0x01
local PRIVATE_CLUSTER_ID = 0x122FFC31
local CHILD_DEVICE_ENDPOINT_ID = 0x06

local child_device_subscribed_attributes = {
  clusters.ColorControl.attributes.CurrentHue,
  clusters.ColorControl.attributes.CurrentSaturation,
  clusters.ColorControl.attributes.CurrentX,
  clusters.ColorControl.attributes.CurrentY,
  clusters.ColorControl.attributes.ColorTemperatureMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
  clusters.ColorControl.attributes.ColorTempPhysicalMinMireds
}

local preference_map = {
  parameter258 = {parameter_number = 258, size = data_types.Boolean}, -- Switch Mode
  parameter22 = {parameter_number = 22, size = data_types.Uint8},     -- Aux Switch Type
  parameter52 = {parameter_number = 52, size = data_types.Boolean},   -- Smart Bulb Mode
  parameter1 = {parameter_number = 1, size = data_types.Uint8},       -- Dimming Speed (Remote)
  parameter2 = {parameter_number = 2, size = data_types.Uint8},       -- Dimming Speed (Local)
  parameter3 = {parameter_number = 3, size = data_types.Uint8},       -- Ramp Rate (Remote)
  parameter4 = {parameter_number = 4, size = data_types.Uint8},       -- Ramp Rate (Local)
  parameter9 = {parameter_number = 9, size = data_types.Uint8},       -- Minimum Level
  parameter10 = {parameter_number = 10, size = data_types.Uint8},     -- Maximum Level
  parameter11 = {parameter_number = 11, size = data_types.Boolean},   -- Invert Switch
  parameter15 = {parameter_number = 15, size = data_types.Uint8},     -- Level After Power Restored
  parameter17 = {parameter_number = 17, size = data_types.Uint8},     -- Load Level Indicator Timeout
  parameter95 = {parameter_number = 95, size = data_types.Uint8},     -- LED Indicator Color (w/On)
  parameter96 = {parameter_number = 96, size = data_types.Uint8},     -- LED Indicator Color (w/Off)
  parameter97 = {parameter_number = 97, size = data_types.Uint8},     -- LED Indicator Intensity (w/On)
  parameter98 = {parameter_number = 98, size = data_types.Uint8}      -- LED Indicator Intensity (w/Off)
}

local function is_inovelli_vtm31_sn(opts, driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and
     device.manufacturer_info.vendor_id == INOVELLI_VTM31_SN_FINGERPRINT.vendor_id and
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

local preferences_calculate_parameter = function(new_value, type, number)
  if number == "parameter9" or number == "parameter10" or number == "parameter15" then
    if new_value == 101 then
      return 255
    else
      return utils.round(new_value / 100 * 254)
    end
  end
  return new_value
end

local function to_boolean(value)
  if value == 0 or value == "0" then
    return false
  end
  return true
end

local function find_default_endpoint(device)
  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  table.sort(switch_eps)
  for _,ep in ipairs(switch_eps) do
    if ep ~= 0 then -- 0 is the matter RootNode endpoint
      return ep
    end
  end
  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return device.MATTER_DEFAULT_ENDPOINT
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%d", ep_id))
end

local function initialize_vtm31_sn(driver, device)
  local main_endpoint = find_default_endpoint(device)
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  local component_map = {}
  local current_component_number = 1
  -- The first switch endpoint will be the main component and the three buttons
  -- will be added as additional components in a MCD profile.
  component_map["main"] = main_endpoint
  table.sort(button_eps)
  for _, ep in ipairs(button_eps) do
    component_map[string.format("button%d", current_component_number)] = ep
    current_component_number = current_component_number + 1
  end
  device:set_field(COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
  buttons.configure(device)
  -- Create a child device for direct control of the LED Notification Bar.
  local name = string.format("%s Notification Bar", device.label)
  driver:try_create_device(
    {
      type = "EDGE_CHILD",
      label = name,
      profile = "light-color-level",
      parent_device_id = device.id,
      parent_assigned_child_key = string.format("%d", CHILD_DEVICE_ENDPOINT_ID),
      vendor_provided_label = name
    }
  )
  device:set_find_child(find_child)
end

local function component_to_endpoint(device, component)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  if map[component] then
    return map[component]
  end
  return find_default_endpoint(device)
end

local function endpoint_to_component(device, ep)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  for component, endpoint in pairs(map) do
    if endpoint == ep then
      return component
    end
  end
  return "main"
end

local function device_init(driver, device)
  device:set_field(LATEST_CLOCK_SET_TIMESTAMP, os.time())
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_find_child(find_child)
  for _, attr in ipairs(child_device_subscribed_attributes) do
    device:add_subscribed_attribute(attr)
  end
  device:subscribe()
end

local function device_added(driver, device)
  device_init(driver, device)
end

local function do_configure(driver, device)
  initialize_vtm31_sn(driver, device)
end

local function driver_switched(driver, device)
  device:try_update_metadata({profile = "inovelli-vtm31-sn"})
  initialize_vtm31_sn(driver, device)
end

local function info_changed(driver, device, event, args)
  local time_diff = 3
  local last_clock_set_time = device:get_field(LATEST_CLOCK_SET_TIMESTAMP)
  if last_clock_set_time ~= nil then
    time_diff = os.difftime(os.time(), last_clock_set_time)
  end
  device:set_field(LATEST_CLOCK_SET_TIMESTAMP, os.time(), {persist = true})
  if time_diff > 2 then -- process preference updates at most once every 2 seconds
    local preferences = preference_map
    for id, value in pairs(device.preferences) do
      if args.old_st_store.preferences[id] ~= value and preferences and preferences[id] then
        if id == "offTransitionTime" then
          local transition_time = math.floor(value)
          device:send(clusters.LevelControl.attributes.OffTransitionTime:write(device, 1, transition_time))
        elseif id == "onTransitionTime" then
          local transition_time = math.floor(value)
          device:send(clusters.LevelControl.attributes.OnTransitionTime:write(device, 1, transition_time))
        else
          local new_parameter_value = preferences_calculate_parameter(preferences_to_numeric_value(device.preferences[id]), preferences[id].size, id)
          if(preferences[id].size == data_types.Boolean) then
            new_parameter_value = to_boolean(new_parameter_value)
          elseif(preferences[id].size == data_types.Uint8) then
            new_parameter_value = math.tointeger(new_parameter_value)
          end
          local data = data_types.validate_or_build_type(new_parameter_value, preferences[id].size)
          device:send(cluster_base.write(device, PRIVATE_CLUSTER_ENDPOINT_ID, PRIVATE_CLUSTER_ID, PRIVATE_CLUSTER_ATTR_ID + preferences[id].parameter_number, nil, data))
        end
      end
    end
  end
  if device.profile.id ~= args.old_st_store.profile.id then
    device:subscribe()
    buttons.configure(device)
  end
end

local inovelli_vtm31_sn_handler = {
  NAME = "inovelli vtm31-sn handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = info_changed,
    doConfigure = do_configure,
    driverSwitched = driver_switched
  },
  can_handle = is_inovelli_vtm31_sn
}

return inovelli_vtm31_sn_handler
