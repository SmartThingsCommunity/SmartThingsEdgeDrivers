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
local common_utils = require "common-utils"
local clusters = require "st.matter.clusters"

local modular_profiles_utils = {}

modular_profiles_utils.SUPPORTED_COMPONENT_CAPABILITIES = "__supported_component_capabilities"

local device_categories = {
  BUTTON = "BUTTON",
  LIGHT = "LIGHT",
  PLUG = "PLUG",
  SWITCH = "SWITCH",
  WATER_VALVE = "WATER_VALVE"
}

local device_type_category_map = {
  [common_utils.ON_OFF_LIGHT_DEVICE_TYPE_ID] = device_categories.LIGHT,
  [common_utils.DIMMABLE_LIGHT_DEVICE_TYPE_ID] = device_categories.LIGHT,
  [common_utils.COLOR_TEMP_LIGHT_DEVICE_TYPE_ID] = device_categories.LIGHT,
  [common_utils.EXTENDED_COLOR_LIGHT_DEVICE_TYPE_ID] = device_categories.LIGHT,
  [common_utils.ON_OFF_PLUG_DEVICE_TYPE_ID] = device_categories.PLUG,
  [common_utils.DIMMABLE_PLUG_DEVICE_TYPE_ID] = device_categories.PLUG,
  [common_utils.ON_OFF_SWITCH_ID] = device_categories.SWITCH,
  [common_utils.ON_OFF_DIMMER_SWITCH_ID] = device_categories.SWITCH,
  [common_utils.ON_OFF_COLOR_DIMMER_SWITCH_ID] = device_categories.SWITCH,
  [common_utils.MOUNTED_ON_OFF_CONTROL_ID] = device_categories.SWITCH,
  [common_utils.MOUNTED_DIMMABLE_LOAD_CONTROL_ID] = device_categories.SWITCH,
  [common_utils.GENERIC_SWITCH_ID] = device_categories.BUTTON,
  [common_utils.WATER_VALVE_ID] = device_categories.WATER_VALVE
}

--- used in a device's profile. The more specific categories are preferred,
--- except for Button, because buttons are included as optional components in
--- every modular profile. Order of preference:
---   1. Light / Plug / Water Valve
---   2. Switch
---   3. Button
function modular_profiles_utils.get_device_category(device)
  local button_found = false
  local switch_found = false
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      local category = device_type_category_map[dt.device_type_id]
      if category == "LIGHT" or category == "PLUG" or category == "WATER_VALVE" then
        return category
      elseif category == device_categories.SWITCH then
        switch_found = true
      elseif category == device_categories.BUTTON then
        button_found = true
      end
    end
  end
  if switch_found then
    return device_categories.SWITCH
  end
  if button_found then
    return device_categories.BUTTON
  end
  -- Return SWITCH as default if no other category is found
  return device_categories.SWITCH
end

local function supports_capability_by_id_modular(device, capability, component)
  if not device:get_field(modular_profiles_utils.SUPPORTED_COMPONENT_CAPABILITIES) then return false end
  for _, component_capabilities in ipairs(device:get_field(modular_profiles_utils.SUPPORTED_COMPONENT_CAPABILITIES)) do
    local comp_id = component_capabilities[1]
    local capability_ids = component_capabilities[2]
    if (component == nil) or (component == comp_id) then
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

local function add_energy_and_power_capabilities(component_capabilities, num_energy_eps, num_power_eps)
  if num_energy_eps > 0 and num_power_eps > 0 then
    table.insert(component_capabilities, capabilities.powerMeter.ID)
    table.insert(component_capabilities, capabilities.energyMeter.ID)
    table.insert(component_capabilities, capabilities.powerConsumptionReport.ID)
  elseif num_energy_eps > 0 then
    table.insert(component_capabilities, capabilities.energyMeter.ID)
    table.insert(component_capabilities, capabilities.powerConsumptionReport.ID)
  elseif num_power_eps > 0 then
    table.insert(component_capabilities, capabilities.powerMeter.ID)
  end
end

local function match_modular_profile(driver, device, battery_attr_support)
  local main_endpoint = common_utils.find_default_endpoint(device)
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  local color_hs_eps = device:get_endpoints(clusters.ColorControl.ID, {feature_bitmap = clusters.ColorControl.types.Feature.HS})
  local color_temp_eps = device:get_endpoints(clusters.ColorControl.ID, {feature_bitmap = clusters.ColorControl.types.Feature.CT})
  local color_xy_eps = device:get_endpoints(clusters.ColorControl.ID, {feature_bitmap = clusters.ColorControl.types.Feature.XY})
  local energy_eps = device:get_endpoints(clusters.ElectricalEnergyMeasurement.ID)
  local fan_eps = device:get_endpoints(clusters.FanControl.ID)
  local humidity_eps = device:get_endpoints(clusters.RelativeHumidityMeasurement.ID)
  local level_eps = device:get_endpoints(clusters.LevelControl.ID)
  local power_eps = device:get_endpoints(clusters.ElectricalPowerMeasurement.ID)
  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  local temperature_eps = device:get_endpoints(clusters.TemperatureMeasurement.ID)
  local valve_eps = device:get_endpoints(clusters.ValveConfigurationAndControl.ID)

  local category = modular_profiles_utils.get_device_category(device)

  local optional_supported_component_capabilities = {}
  local main_component_capabilities = {}
  local extra_component_capabilities = {}

  local MAIN_COMPONENT_IDX = 1
  local CAPABILITIES_LIST_IDX = 2

  if #button_eps > 0 then
    for component_num, _ in ipairs(button_eps) do
      -- button-modular profile uses 'main', 'button2', button3', ... as component names.
      -- Other profiles use 'main', 'button', 'button2', etc
      if component_num == 1 and category == "BUTTON" then
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

  if #fan_eps > 0 then
    table.insert(main_component_capabilities, capabilities.fanMode.ID)
    table.insert(main_component_capabilities, capabilities.fanSpeedPercent.ID)
  end

  if #humidity_eps > 0 then
    table.insert(main_component_capabilities, capabilities.relativeHumidityMeasurement.ID)
  end

  add_energy_and_power_capabilities(main_component_capabilities, #energy_eps, #power_eps)

  if #switch_eps > 0 then
    if category == "PLUG" then
      for component_num, ep in ipairs(switch_eps) do
        if component_num ~= 1 then
          local plug_capabilities = {}
          table.insert(plug_capabilities, capabilities.switch.ID)
          if common_utils.tbl_contains(level_eps, ep) then
            table.insert(plug_capabilities, capabilities.switchLevel.ID)
          end
          add_energy_and_power_capabilities(plug_capabilities, #energy_eps, #power_eps)
          local component_name = "plug" .. component_num
          table.insert(extra_component_capabilities, {component_name, plug_capabilities})
        end
      end
    elseif category == "BUTTON" or category == "WATER_VALVE" then
      table.insert(main_component_capabilities, capabilities.switch.ID)
    else -- category = LIGHT or SWITCH
      local num_switch_server_eps = common_utils.build_child_switch_profiles(driver, device, main_endpoint)
      if num_switch_server_eps > 0 and common_utils.detect_matter_thing(device) then
        -- Ensure that the proper capabilities are included for Light Switch
        -- device types that implement the OnOff cluster as 'server'
        local device_type_id = common_utils.handle_light_switch_with_onOff_server_clusters(device, main_endpoint, true)
        if common_utils.ON_OFF_SWITCH_ID <= device_type_id and device_type_id <= common_utils.ON_OFF_COLOR_DIMMER_SWITCH_ID then
          local capabilities_to_remove = {}
          if device_type_id == common_utils.ON_OFF_SWITCH_ID then
            capabilities_to_remove = {capabilities.colorControl.ID, capabilities.colorTemperature.ID, capabilities.switchLevel.ID}
          elseif device_type_id == common_utils.ON_OFF_DIMMER_SWITCH_ID then
            capabilities_to_remove = {capabilities.colorControl.ID, capabilities.colorTemperature.ID}
            if not common_utils.tbl_contains(main_component_capabilities, capabilities.switchLevel.ID) then
              table.insert(main_component_capabilities, capabilities.switchLevel.ID)
            end
          else -- device_type_id = ON_OFF_COLOR_DIMMER_SWITCH_ID
            if not common_utils.tbl_contains(main_component_capabilities, capabilities.switchLevel.ID) then
              table.insert(main_component_capabilities, capabilities.switchLevel.ID)
            end
            if not common_utils.tbl_contains(main_component_capabilities, capabilities.colorTemperature.ID) then
              table.insert(main_component_capabilities, capabilities.colorTemperature.ID)
            end
            if not common_utils.tbl_contains(main_component_capabilities, capabilities.colorControl.ID) then
              table.insert(main_component_capabilities, capabilities.colorControl.ID)
            end
          end
          for _, capability in ipairs(capabilities_to_remove) do
            local _, found_idx = common_utils.tbl_contains(main_component_capabilities, capability)
            if found_idx then
              table.remove(main_component_capabilities, found_idx)
            end
          end
        end
      end
    end
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

  local total_supported_capabilities = optional_supported_component_capabilities

  local profile_name, mandatory_capability_for_device_category
  if category == "BUTTON" then
    profile_name = "button-modular"
    mandatory_capability_for_device_category = capabilities.button.ID
  elseif category == "LIGHT" then
    profile_name = "light-modular"
    mandatory_capability_for_device_category = capabilities.switch.ID
  elseif category == "PLUG" then
    profile_name = "plug-modular"
    mandatory_capability_for_device_category = capabilities.switch.ID
  elseif category == "WATER_VALVE" then
    profile_name = "water-valve-modular"
    mandatory_capability_for_device_category = capabilities.valve.ID
  else -- category = SWITCH
    profile_name = "switch-modular"
    mandatory_capability_for_device_category = capabilities.switch.ID
  end

  device:try_update_metadata({profile = profile_name, optional_component_capabilities = optional_supported_component_capabilities})

  -- add mandatory capabilities for subscription
  table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX], mandatory_capability_for_device_category)
  table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX], capabilities.refresh.ID)
  table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX], capabilities.firmwareUpdate.ID)

  device:set_field(modular_profiles_utils.SUPPORTED_COMPONENT_CAPABILITIES, total_supported_capabilities, {persist = true})
  -- re-up subscription with new capabilities using the modular supports_capability override
  device:extend_device("supports_capability_by_id", supports_capability_by_id_modular)
end

function modular_profiles_utils.match_profile(driver, device)
  if #device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY}) == 0 then
    match_modular_profile(driver, device)
  else
    device:send(clusters.PowerSource.attributes.AttributeList:read(device)) -- battery profiles are configured by power_source_attribute_list_handler
  end
end

function modular_profiles_utils.power_source_attribute_list_handler(driver, device, ib, response)
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
  match_modular_profile(driver, device, battery_attr_support)
end

return modular_profiles_utils
