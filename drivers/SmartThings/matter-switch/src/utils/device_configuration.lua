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

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "utils.embedded_cluster_utils"
local version = require "version"

local fields = require "utils.switch_fields"
local switch_utils = require "utils.switch_utils"

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded_clusters.ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "embedded_clusters.ElectricalPowerMeasurement"
  clusters.ValveConfigurationAndControl = require "embedded_clusters.ValveConfigurationAndControl"
end

local DeviceConfiguration = {}
local SwitchDeviceConfiguration = {}
local ButtonDeviceConfiguration = {}

function SwitchDeviceConfiguration.assign_profile_for_onoff_ep(device, onoff_ep_id, is_child_device)
  local ep = switch_utils.get_endpoint_info(device, onoff_ep_id)
  local primary_dt_id = switch_utils.find_max_subset_device_type(ep, fields.DEVICE_TYPE_ID.LIGHT)
    or (switch_utils.detect_matter_thing(device) and switch_utils.find_max_subset_device_type(ep, fields.DEVICE_TYPE_ID.SWITCH))
    or ep.device_types[1] and ep.device_types[1].device_type_id
  local profile = fields.device_type_profile_map[primary_dt_id]

  if is_child_device then
    -- Check if device has an overridden child profile that differs from the profile that would match
    -- the child's device type for the following two cases:
    --   1. To add Electrical Sensor only to the first EDGE_CHILD (light-power-energy-powerConsumption)
    --      for the Aqara Light Switch H2. The profile of the second EDGE_CHILD for this device is
    --      determined in the "for" loop above (e.g., light-binary)
    --   2. The selected profile for the child device matches the initial profile defined in
    --      child_device_profile_overrides
    for _, vendor in pairs(fields.child_device_profile_overrides_per_vendor_id) do
      for _, fingerprint in ipairs(vendor) do
        if device.manufacturer_info.product_id == fingerprint.product_id and
           ((device.manufacturer_info.vendor_id == fields.AQARA_MANUFACTURER_ID and onoff_ep_id == 1) or profile == fingerprint.initial_profile) then
            return fingerprint.target_profile
        end
      end
    end

    -- default to "switch-binary" if no profile is found
    return profile or "switch-binary"
  end

  return profile
end

function SwitchDeviceConfiguration.create_or_update_child_devices(driver, device, server_onoff_ep_ids, main_endpoint_id)
  if #server_onoff_ep_ids == 1 and server_onoff_ep_ids[1] == main_endpoint_id then -- no children will exist
   return
  end

  local device_num = 0
  table.sort(server_onoff_ep_ids)
  for idx, ep_id in ipairs(server_onoff_ep_ids) do
    device_num = device_num + 1
    if ep_id ~= main_endpoint_id then -- don't create a child device that maps to the main endpoint
      local child_device_name = string.format("%s %d", device.label, device_num)
      local child_profile = SwitchDeviceConfiguration.assign_profile_for_onoff_ep(device, ep_id, true)
      local existing_child_device = device:get_field(fields.IS_PARENT_CHILD_DEVICE) and switch_utils.find_child(device, ep_id)
      if not existing_child_device then
        driver:try_create_device({
          type = "EDGE_CHILD",
          label = child_device_name,
          profile = child_profile,
          parent_device_id = device.id,
          parent_assigned_child_key = string.format("%d", ep_id),
          vendor_provided_label = child_device_name
        })
      else
        existing_child_device:try_update_metadata({
          profile = child_profile
        })
      end
      if idx == 1 and string.find(child_profile, "energy") then
        -- when energy management is defined in the root endpoint(0), replace it with the first switch endpoint and process it.
        device:set_field(fields.ENERGY_MANAGEMENT_ENDPOINT, ep_id, {persist = true})
      end
    end
  end

  -- Persist so that the find_child function is always set on each driver init.
  device:set_field(fields.IS_PARENT_CHILD_DEVICE, true, {persist = true})
  device:set_find_child(switch_utils.find_child)
end

function ButtonDeviceConfiguration.update_button_profile(device, main_endpoint, num_button_eps)
  local profile_name = string.gsub(num_button_eps .. "-button", "1%-", "") -- remove the "1-" in a device with 1 button ep
  if switch_utils.device_type_supports_button_switch_combination(device, main_endpoint) then
    profile_name = "light-level-" .. profile_name
  end
  local battery_supported = #device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY}) > 0
  if battery_supported then -- battery profiles are configured later, in power_source_attribute_list_handler
    device:send(clusters.PowerSource.attributes.AttributeList:read(device))
  else
    device:try_update_metadata({profile = profile_name})
  end
end

function ButtonDeviceConfiguration.update_button_component_map(device, main_endpoint, button_eps)
  -- create component mapping on the main profile button endpoints
  table.sort(button_eps)
  local component_map = {}
  component_map["main"] = main_endpoint
  for component_num, ep in ipairs(button_eps) do
    if ep ~= main_endpoint then
      local button_component = "button"
      if #button_eps > 1 then
        button_component = button_component .. component_num
      end
      component_map[button_component] = ep
    end
  end
  device:set_field(fields.COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
end


function ButtonDeviceConfiguration.configure_buttons(device)
  local ms_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  local msr_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_RELEASE})
  local msl_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS})
  local msm_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS})

  for _, ep in ipairs(ms_eps or {}) do
    if device.profile.components[switch_utils.endpoint_to_component(device, ep)] then
      device.log.info_with({hub_logs=true}, string.format("Configuring Supported Values for generic switch endpoint %d", ep))
      local supportedButtonValues_event
      -- this ordering is important, since MSM & MSL devices must also support MSR
      if switch_utils.tbl_contains(msm_eps, ep) then
        supportedButtonValues_event = nil -- deferred to the max press handler
        device:send(clusters.Switch.attributes.MultiPressMax:read(device, ep))
        switch_utils.set_field_for_endpoint(device, fields.SUPPORTS_MULTI_PRESS, ep, true, {persist = true})
      elseif switch_utils.tbl_contains(msl_eps, ep) then
        supportedButtonValues_event = capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})
      elseif switch_utils.tbl_contains(msr_eps, ep) then
        supportedButtonValues_event = capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})
        switch_utils.set_field_for_endpoint(device, fields.EMULATE_HELD, ep, true, {persist = true})
      else -- this switch endpoint only supports momentary switch, no release events
        supportedButtonValues_event = capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})
        switch_utils.set_field_for_endpoint(device, fields.INITIAL_PRESS_ONLY, ep, true, {persist = true})
      end

      if supportedButtonValues_event then
        device:emit_event_for_endpoint(ep, supportedButtonValues_event)
      end
      device:emit_event_for_endpoint(ep, capabilities.button.button.pushed({state_change = false}))
    else
      device.log.info_with({hub_logs=true}, string.format("Component not found for generic switch endpoint %d. Skipping Supported Value configuration", ep))
    end
  end
end


-- [[ PROFILE MATCHING AND CONFIGURATIONS ]] --

function DeviceConfiguration.match_profile(driver, device)
  local main_endpoint_id = switch_utils.find_default_endpoint(device)
  local updated_profile = nil

  local valve_eps = embedded_cluster_utils.get_endpoints(device, clusters.ValveConfigurationAndControl.ID)
  if #valve_eps > 0 then
    updated_profile = "water-valve"
    if #embedded_cluster_utils.get_endpoints(device, clusters.ValveConfigurationAndControl.ID,
      {feature_bitmap = clusters.ValveConfigurationAndControl.types.Feature.LEVEL}) > 0 then
      updated_profile = updated_profile .. "-level"
    end
  end

  local server_onoff_ep_ids = device:get_endpoints(clusters.OnOff.ID, { cluster_type = "SERVER" })
  if #server_onoff_ep_ids > 0 then
    SwitchDeviceConfiguration.create_or_update_child_devices(driver, device, server_onoff_ep_ids, main_endpoint_id)
    updated_profile = SwitchDeviceConfiguration.assign_profile_for_onoff_ep(device, main_endpoint_id)
    local find_substr = function(s, p) return string.find(s or "", p, 1, true) end

    if find_substr(updated_profile, "plug-binary") or find_substr(updated_profile, "plug-level") then
      local electrical_tags = ""
      if #embedded_cluster_utils.get_endpoints(device, clusters.ElectricalPowerMeasurement.ID) > 0 then electrical_tags = electrical_tags .. "-power" end
      if #embedded_cluster_utils.get_endpoints(device, clusters.ElectricalEnergyMeasurement.ID) > 0 then electrical_tags = electrical_tags .. "-energy-powerConsumption" end
      if electrical_tags ~= "" then updated_profile = string.gsub(updated_profile, "-binary", "") .. electrical_tags end
    elseif find_substr(updated_profile, "light-color-level") and #device:get_endpoints(clusters.FanControl.ID) > 0 then
      updated_profile = "light-color-level-fan"
    elseif find_substr(updated_profile, "light-level") and #device:get_endpoints(clusters.OccupancySensing.ID) > 0 then
      updated_profile = "light-level-motion"
    elseif find_substr(updated_profile, "light-level-colorTemperature") or find_substr(updated_profile, "light-color-level") then
      -- ignore attempts to dynamically profile light-level-colorTemperature and light-color-level devices for now, since
      -- these may lose fingerprinted Kelvin ranges when dynamically profiled.
      return
    end
  end

  -- initialize the main device card with buttons if applicable
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  if switch_utils.tbl_contains(fields.STATIC_BUTTON_PROFILE_SUPPORTED, #button_eps) then
    ButtonDeviceConfiguration.update_button_profile(device, main_endpoint_id, #button_eps)
    -- All button endpoints found will be added as additional components in the profile containing the main_endpoint.
    ButtonDeviceConfiguration.update_button_component_map(device, main_endpoint_id, button_eps)
    ButtonDeviceConfiguration.configure_buttons(device)
    return
  end

  device:try_update_metadata({ profile = updated_profile })
end

return {
  DeviceCfg = DeviceConfiguration,
  SwitchCfg = SwitchDeviceConfiguration,
  ButtonCfg = ButtonDeviceConfiguration
}