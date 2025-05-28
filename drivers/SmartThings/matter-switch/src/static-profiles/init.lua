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

local button_utils = require "button-utils"
local clusters = require "st.matter.clusters"
local common_utils = require "common-utils"
local device_lib = require "st.device"
local embedded_cluster_utils = require "embedded-cluster-utils"

-------------------------------------------------------------------------------------
-- Static Profile sub-driver
--   Used for environments that don't support modular profiles.
-------------------------------------------------------------------------------------

--- find_default_endpoint helper function to handle situations where the device
--- does not have endpoint ids in sequential order from 1.
local function find_default_endpoint(device)
  if device.manufacturer_info.vendor_id == common_utils.AQARA_MANUFACTURER_ID and
    device.manufacturer_info.product_id == common_utils.AQARA_CLIMATE_SENSOR_W100_ID then
    -- In case of Aqara Climate Sensor W100, in order to sequentially set the button name to button 1, 2, 3
    return device.MATTER_DEFAULT_ENDPOINT
  end
  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  -- Return the first switch endpoint as the default endpoint if no button endpoints are present
  if #button_eps == 0 and #switch_eps > 0 then
    return common_utils.get_first_non_zero_endpoint(switch_eps)
  end
  -- Return the first button endpoint as the default endpoint if no switch endpoints are present
  if #switch_eps == 0 and #button_eps > 0 then
    return common_utils.get_first_non_zero_endpoint(button_eps)
  end
  -- If both switch and button endpoints are present, check the device type on the main switch
  -- endpoint. If it is not a supported device type, return the first button endpoint as the
  -- default endpoint.
  if #switch_eps > 0 and #button_eps > 0 then
    local main_endpoint = common_utils.get_first_non_zero_endpoint(switch_eps)
    if common_utils.supports_modular_profile(device) or common_utils.device_type_supports_button_switch_combination(device, main_endpoint) then
      return common_utils.get_first_non_zero_endpoint(switch_eps)
    else
      device.log.warn("The main switch endpoint does not contain a supported device type for a component configuration with buttons")
      return common_utils.get_first_non_zero_endpoint(button_eps)
    end
  end
  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return device.MATTER_DEFAULT_ENDPOINT
end

local function handle_light_switch_with_onOff_server_clusters(device, main_endpoint)
  local cluster_id = 0
  for _, ep in ipairs(device.endpoints) do
    -- main_endpoint only supports server cluster by definition of get_endpoints()
    if main_endpoint == ep.endpoint_id then
      for _, dt in ipairs(ep.device_types) do
        -- no device type that is not in the switch subset should be considered.
        if (common_utils.ON_OFF_SWITCH_ID <= dt.device_type_id and dt.device_type_id <= common_utils.ON_OFF_COLOR_DIMMER_SWITCH_ID) then
          cluster_id = math.max(cluster_id, dt.device_type_id)
        end
      end
      break
    end
  end
  if common_utils.device_type_profile_map[cluster_id] then
    device:try_update_metadata({profile = common_utils.device_type_profile_map[cluster_id]})
  end
end

local function initialize_buttons_and_switches(driver, device, main_endpoint)
  local profile_found = false
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  if common_utils.tbl_contains(button_utils.STATIC_BUTTON_PROFILE_SUPPORTED, #button_eps) then
    button_utils.build_button_component_map(device, main_endpoint, button_eps)
    button_utils.build_button_profile(device, main_endpoint, #button_eps)
    -- All button endpoints found will be added as additional components in the profile containing the main_endpoint.
    -- The resulting endpoint to component map is saved in the COMPONENT_TO_ENDPOINT_MAP field
    button_utils.configure_buttons(device)
    profile_found = true
  end
  -- Without support for bindings, only clusters that are implemented as server are counted. This count is handled
  -- while building switch child profiles
  local num_switch_server_eps = common_utils.build_child_switch_profiles(driver, device, main_endpoint)
  -- We do not support the Light Switch device types because they require OnOff to be implemented as 'client', which requires us to support bindings.
  -- However, this workaround profiles devices that claim to be Light Switches, but that break spec and implement OnOff as 'server'.
  -- Note: since their device type isn't supported, these devices join as a matter-thing.
  if num_switch_server_eps > 0 and common_utils.detect_matter_thing(device) then
    handle_light_switch_with_onOff_server_clusters(device, main_endpoint)
    profile_found = true
  end
  return profile_found
end

local function match_profile(driver, device)
  local main_endpoint = find_default_endpoint(device)
  -- initialize the main device card with buttons if applicable, and create child devices as needed for multi-switch devices.
  local profile_found = initialize_buttons_and_switches(driver, device, main_endpoint)
  if device:get_field(common_utils.IS_PARENT_CHILD_DEVICE) then
    device:set_find_child(common_utils.find_child)
  end
  if profile_found then
    return
  end
  local fan_eps = device:get_endpoints(clusters.FanControl.ID)
  local level_eps = device:get_endpoints(clusters.LevelControl.ID)
  local energy_eps = embedded_cluster_utils.get_endpoints(device, clusters.ElectricalEnergyMeasurement.ID)
  local power_eps = embedded_cluster_utils.get_endpoints(device, clusters.ElectricalPowerMeasurement.ID)
  local valve_eps = embedded_cluster_utils.get_endpoints(device, clusters.ValveConfigurationAndControl.ID)
  local profile_name
  local level_support = ""
  if #level_eps > 0 then
    level_support = "-level"
  end
  if #energy_eps > 0 and #power_eps > 0 then
    profile_name = "plug" .. level_support .. "-power-energy-powerConsumption"
  elseif #energy_eps > 0 then
    profile_name = "plug" .. level_support .. "-energy-powerConsumption"
  elseif #power_eps > 0 then
    profile_name = "plug" .. level_support .. "-power"
  elseif #valve_eps > 0 then
    profile_name = "water-valve"
    if #embedded_cluster_utils.get_endpoints(device, clusters.ValveConfigurationAndControl.ID,
      {feature_bitmap = clusters.ValveConfigurationAndControl.types.Feature.LEVEL}) > 0 then
      profile_name = profile_name .. "-level"
    end
  elseif #fan_eps > 0 then
    profile_name = "light-color-level-fan"
  end
  if profile_name then
    device:try_update_metadata({ profile = profile_name })
  end
end

local function device_init(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then
    common_utils.check_field_name_updates(device)
    device:set_component_to_endpoint_fn(common_utils.component_to_endpoint)
    device:set_endpoint_to_component_fn(common_utils.endpoint_to_component)
    if device:get_field(common_utils.IS_PARENT_CHILD_DEVICE) then
      device:set_find_child(common_utils.find_child)
    end
    local main_endpoint = find_default_endpoint(device)
    -- ensure subscription to all endpoint attributes- including those mapped to child devices
    common_utils.add_subscribed_attributes_and_events(device, main_endpoint)
    device:subscribe()
  end
end

local function do_configure(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and not common_utils.detect_bridge(device) then
    match_profile(driver, device)
  end
end

local function driver_switched(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and not common_utils.detect_bridge(device) then
    match_profile(driver, device)
  end
end

local function power_source_attribute_list_handler(driver, device, ib, response)
  local battery_attr_support
  for _, attr in ipairs(ib.data.elements) do
    -- Re-profile the device if BatPercentRemaining (Attribute ID 0x0C) or
    -- BatChargeLevel (Attribute ID 0x0E) is present.
    if attr.value == 0x0C then
      battery_attr_support = common_utils.battery_support.BATTERY_PERCENTAGE
      break
    elseif attr.value == 0x0E then
      battery_attr_support = common_utils.battery_support.BATTERY_LEVEL
      break
    end
  end
  local profile_name
  if battery_attr_support == common_utils.battery_support.BATTERY_PERCENTAGE then
    profile_name = "button-battery"
  elseif battery_attr_support == common_utils.battery_support.BATTERY_LEVEL then
    profile_name = "button-batteryLevel"
  end
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  if #button_eps > 1 then
    profile_name = string.format("%d-", #button_eps) .. profile_name
  end
  if device.manufacturer_info.vendor_id == common_utils.AQARA_MANUFACTURER_ID and
    device.manufacturer_info.product_id == common_utils.AQARA_CLIMATE_SENSOR_W100_ID then
    profile_name = profile_name .. "-temperature-humidity"
  end
  if profile_name then
    device:try_update_metadata({ profile = profile_name })
  end
end

local static_profile_handler = {
  NAME = "Static Profile Handler",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
    driverSwitched = driver_switched
  },
  matter_handlers = {
    attr = {
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.AttributeList.ID] = power_source_attribute_list_handler
      }
    }
  },
  can_handle = common_utils.is_static_profile_device
}

return static_profile_handler
