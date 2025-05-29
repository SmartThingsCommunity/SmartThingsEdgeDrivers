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
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local common_utils = require "common-utils"

local modular_profiles_utils = {}

modular_profiles_utils.SUPPORTED_COMPONENT_CAPABILITIES = "__supported_component_capabilities"


local profile_name_and_mandatory_capability_per_device_category = {
  [common_utils.device_categories.BUTTON] =      { profile_name = "button-modular", mandatory_capability = capabilities.button.ID },
  [common_utils.device_categories.LIGHT] =       { profile_name = "light-modular",  mandatory_capability = capabilities.switch.ID },
  [common_utils.device_categories.PLUG] =        { profile_name = "plug-modular",   mandatory_capability = capabilities.switch.ID },
  [common_utils.device_categories.SWITCH] =      { profile_name = "switch-modular", mandatory_capability = capabilities.valve.ID },
  [common_utils.device_categories.WATER_VALVE] = { profile_name = "water-valve-modular",  mandatory_capability = capabilities.switch.ID }
}

local function supports_capability_by_id_modular(device, capability, component)
  local supported_component_capabilities = device:get_field(modular_profiles_utils.SUPPORTED_COMPONENT_CAPABILITIES) or {}
  for _, component_capabilities in ipairs(supported_component_capabilities) do
    local comp_id = component_capabilities[1]
    local capability_ids = component_capabilities[2]
    if component == nil or component == comp_id then
      for _, cap in ipairs(capability_ids) do
        if cap == capability then
          return true
        end
      end
    end
  end
  return false
end

local function add_battery_capability(component_capabilities, battery_attr_support)
  if battery_attr_support == common_utils.battery_support.BATTERY_PERCENTAGE then
    table.insert(component_capabilities, capabilities.battery.ID)
  elseif battery_attr_support == common_utils.battery_support.BATTERY_LEVEL then
    table.insert(component_capabilities, capabilities.batteryLevel.ID)
  end
end

local function add_button_capabilities(device, category, main_endpoint, main_component_capabilities, extra_component_capabilities, battery_attr_support)
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  if #button_eps == 0 then return end
  for component_num, _ in ipairs(button_eps) do
    -- button-modular profile uses 'main', 'button2', button3', ... as component names.
    -- Other profiles use 'main', 'button', 'button2', etc
    if component_num == 1 and category == common_utils.device_categories.BUTTON then
      table.insert(main_component_capabilities, capabilities.button.ID)
      if battery_attr_support then
        add_battery_capability(main_component_capabilities, battery_attr_support)
      end
    else
      local button_capabilities = {}
      table.insert(button_capabilities, capabilities.button.ID)
      if component_num == 1 and battery_attr_support then
        add_battery_capability(button_capabilities, battery_attr_support)
      end
      local component_name = "button"
      if component_num > 1 then
        component_name = component_name .. component_num
      end
      table.insert(extra_component_capabilities, {component_name, button_capabilities})
    end
  end
  button_utils.build_button_component_map(device, main_endpoint, button_eps)
  button_utils.configure_buttons(device)
end

local function handle_light_switch_with_onOff_server_clusters(device, main_endpoint, component_capabilities)
  local device_type_id = 0
  for _, ep in ipairs(device.endpoints) do
    -- main_endpoint only supports server cluster by definition of get_endpoints()
    if main_endpoint == ep.endpoint_id then
      for _, dt in ipairs(ep.device_types) do
        -- no device type that is not in the switch subset should be considered.
        if (common_utils.ON_OFF_SWITCH_ID <= dt.device_type_id and dt.device_type_id <= common_utils.ON_OFF_COLOR_DIMMER_SWITCH_ID) then
          device_type_id = math.max(device_type_id, dt.device_type_id)
        end
      end
      break
    end
  end
  if device_type_id == 0 then return end
  local capabilities_to_remove = {}
  if device_type_id == common_utils.ON_OFF_SWITCH_ID then
    capabilities_to_remove = {capabilities.colorControl.ID, capabilities.colorTemperature.ID, capabilities.switchLevel.ID}
  elseif device_type_id == common_utils.ON_OFF_DIMMER_SWITCH_ID then
    capabilities_to_remove = {capabilities.colorControl.ID, capabilities.colorTemperature.ID}
    if not common_utils.tbl_contains(component_capabilities, capabilities.switchLevel.ID) then
      table.insert(component_capabilities, capabilities.switchLevel.ID)
    end
  else -- device_type_id = ON_OFF_COLOR_DIMMER_SWITCH_ID
    if not common_utils.tbl_contains(component_capabilities, capabilities.switchLevel.ID) then
      table.insert(component_capabilities, capabilities.switchLevel.ID)
    end
    if not common_utils.tbl_contains(component_capabilities, capabilities.colorTemperature.ID) then
      table.insert(component_capabilities, capabilities.colorTemperature.ID)
    end
    if not common_utils.tbl_contains(component_capabilities, capabilities.colorControl.ID) then
      table.insert(component_capabilities, capabilities.colorControl.ID)
    end
  end
  for _, capability in ipairs(capabilities_to_remove) do
    local _, found_idx = common_utils.tbl_contains(component_capabilities, capability)
    if found_idx then
      table.remove(component_capabilities, found_idx)
    end
  end
end

local function match_modular_profile(driver, device, battery_attr_support)
  local main_endpoint = common_utils.find_default_endpoint(device)
  local color_hs_eps = device:get_endpoints(clusters.ColorControl.ID, {feature_bitmap = clusters.ColorControl.types.Feature.HS})
  local color_xy_eps = device:get_endpoints(clusters.ColorControl.ID, {feature_bitmap = clusters.ColorControl.types.Feature.XY})
  local color_temp_eps = device:get_endpoints(clusters.ColorControl.ID, {feature_bitmap = clusters.ColorControl.types.Feature.CT})
  local level_eps = device:get_endpoints(clusters.LevelControl.ID)
  local power_eps = device:get_endpoints(clusters.ElectricalPowerMeasurement.ID)
  local energy_eps = device:get_endpoints(clusters.ElectricalEnergyMeasurement.ID)
  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  local fan_eps = device:get_endpoints(clusters.FanControl.ID)
  local humidity_eps = device:get_endpoints(clusters.RelativeHumidityMeasurement.ID)
  local temperature_eps = device:get_endpoints(clusters.TemperatureMeasurement.ID)
  local valve_eps = device:get_endpoints(clusters.ValveConfigurationAndControl.ID)

  local category = common_utils.get_device_category(device, main_endpoint)

  local optional_supported_component_capabilities = {}
  local main_component_capabilities = {}
  local extra_component_capabilities = {}

  local MAIN_COMPONENT_IDX, CAPABILITIES_LIST_IDX = 1, 2

  add_button_capabilities(device, category, main_endpoint, main_component_capabilities, extra_component_capabilities, battery_attr_support)

  -- Only add capabilities related to lights if the corresponding cluster is
  -- implemented on the main endpoint. Otherwise, it will be added as a child device.
  if common_utils.tbl_contains(color_hs_eps, main_endpoint) or common_utils.tbl_contains(color_xy_eps, main_endpoint) then
    table.insert(main_component_capabilities, capabilities.colorControl.ID)
  end

  if common_utils.tbl_contains(color_temp_eps, main_endpoint) then
    table.insert(main_component_capabilities, capabilities.colorTemperature.ID)
  end

  if common_utils.tbl_contains(level_eps, main_endpoint) then
    table.insert(main_component_capabilities, capabilities.switchLevel.ID)
  end

  if #power_eps > 0 then
    table.insert(main_component_capabilities, capabilities.powerMeter.ID)
  end

  if #energy_eps > 0 then
    table.insert(main_component_capabilities, capabilities.energyMeter.ID)
    table.insert(main_component_capabilities, capabilities.powerConsumptionReport.ID)
  end

  if #switch_eps > 0 then
    -- If the device is a Button or Water Valve, add the switch capability since
    -- it is not a mandatory capability for these device types.
    if category == common_utils.device_categories.BUTTON or category == common_utils.device_categories.WATER_VALVE then
      table.insert(main_component_capabilities, capabilities.switch.ID)
    end
    -- Without support for bindings, only clusters that are implemented as server are counted. This count is handled
    -- while building switch child profiles
    local num_switch_server_eps = common_utils.build_child_switch_profiles(driver, device, main_endpoint)
    -- Ensure that the proper capabilities are included for Light Switch device types that implement the OnOff
    -- cluster as 'server'
    if num_switch_server_eps > 0 and common_utils.detect_matter_thing(device) then
      handle_light_switch_with_onOff_server_clusters(device, main_endpoint, main_component_capabilities)
    end
  end

  if #fan_eps > 0 then
    table.insert(main_component_capabilities, capabilities.fanMode.ID)
    table.insert(main_component_capabilities, capabilities.fanSpeedPercent.ID)
  end

  if #humidity_eps > 0 then
    table.insert(main_component_capabilities, capabilities.relativeHumidityMeasurement.ID)
  end

  if #temperature_eps > 0 then
    table.insert(main_component_capabilities, capabilities.temperatureMeasurement.ID)
  end

  if #valve_eps > 0 then
    table.insert(main_component_capabilities, capabilities.valve.ID)
    if #device:get_endpoints(clusters.ValveConfigurationAndControl.ID,
      {feature_bitmap = clusters.ValveConfigurationAndControl.types.Feature.LEVEL}) > 0 then
      table.insert(main_component_capabilities, capabilities.level.ID)
    end
  end

  table.insert(optional_supported_component_capabilities, {"main", main_component_capabilities})
  for _, component_capability in ipairs(extra_component_capabilities) do
    table.insert(optional_supported_component_capabilities, component_capability)
  end

  device:try_update_metadata({profile = profile_name_and_mandatory_capability_per_device_category[category].profile_name,
                              optional_component_capabilities = optional_supported_component_capabilities})

  local total_supported_capabilities = optional_supported_component_capabilities
  -- Add mandatory capabilities for subscription
  table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX],
    profile_name_and_mandatory_capability_per_device_category[category].mandatory_capability)
  table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX], capabilities.refresh.ID)
  table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX], capabilities.firmwareUpdate.ID)

  device:set_field(modular_profiles_utils.SUPPORTED_COMPONENT_CAPABILITIES, total_supported_capabilities, {persist = true})
  -- Re-up subscription with new capabilities using the modular supports_capability override
  device:extend_device("supports_capability_by_id", supports_capability_by_id_modular)
end

function modular_profiles_utils.match_profile(driver, device)
  if #device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY}) == 0 then
    match_modular_profile(driver, device)
  else
    device:send(clusters.PowerSource.attributes.AttributeList:read(device)) -- battery profiles are configured by power_source_attribute_list_handler
  end
end

return modular_profiles_utils
