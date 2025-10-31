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

function SwitchDeviceConfiguration.assign_profile_for_onoff_ep(device, server_onoff_ep_id, is_child_device)
  local ep_info = switch_utils.get_endpoint_info(device, server_onoff_ep_id)

  -- per spec, the Switch device types support OnOff as CLIENT, though some vendors break spec and support it as SERVER.
  local primary_dt_id = switch_utils.find_max_subset_device_type(ep_info, fields.DEVICE_TYPE_ID.LIGHT)
    or switch_utils.find_max_subset_device_type(ep_info, fields.DEVICE_TYPE_ID.SWITCH)
    or ep_info.device_types[1] and ep_info.device_types[1].device_type_id

  local generic_profile = fields.device_type_profile_map[primary_dt_id]

  local static_electrical_tags = switch_utils.get_field_for_endpoint(device, fields.ELECTRICAL_TAGS, server_onoff_ep_id)
  if static_electrical_tags ~= nil then
    generic_profile = string.gsub(generic_profile, "-binary", "") .. static_electrical_tags
  end

  if is_child_device and generic_profile == switch_utils.get_product_override_field(device, "initial_profile") then
    generic_profile = switch_utils.get_product_override_field(device, "target_profile") or generic_profile
  end

  -- if no supported device type is found, return switch-binary as a generic "OnOff EP" profile
  return generic_profile or "switch-binary"
end

function SwitchDeviceConfiguration.create_child_devices(driver, device, server_onoff_ep_ids, default_endpoint_id)
  if #server_onoff_ep_ids == 1 and server_onoff_ep_ids[1] == default_endpoint_id then -- no children will be created
   return
  end

  local device_num = 0
  table.sort(server_onoff_ep_ids)
  for idx, ep_id in ipairs(server_onoff_ep_ids) do
    device_num = device_num + 1
    if ep_id ~= default_endpoint_id then -- don't create a child device that maps to the main endpoint
      local label_and_name = string.format("%s %d", device.label, device_num)
      driver:try_create_device(
        {
          type = "EDGE_CHILD",
          label = label_and_name,
          profile = SwitchDeviceConfiguration.assign_profile_for_onoff_ep(device, ep_id, true),
          parent_device_id = device.id,
          parent_assigned_child_key = string.format("%d", ep_id),
          vendor_provided_label = label_and_name
        }
      )
    end
  end

  -- Persist so that the find_child function is always set on each driver init.
  device:set_field(fields.IS_PARENT_CHILD_DEVICE, true, {persist = true})
  device:set_find_child(switch_utils.find_child)
end

function ButtonDeviceConfiguration.update_button_profile(device, default_endpoint_id, num_button_eps)
  local profile_name = string.gsub(num_button_eps .. "-button", "1%-", "") -- remove the "1-" in a device with 1 button ep
  if switch_utils.device_type_supports_button_switch_combination(device, default_endpoint_id) then
    profile_name = "light-level-" .. profile_name
  end
  local motion_eps = device:get_endpoints(clusters.OccupancySensing.ID)
  if #motion_eps > 0 and (num_button_eps == 3 or num_button_eps == 6) then -- only these two devices are handled
    profile_name = profile_name .. "-motion"
  end
  local battery_supported = #device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY}) > 0
  if battery_supported then -- battery profiles are configured later, in power_source_attribute_list_handler
    device:send(clusters.PowerSource.attributes.AttributeList:read(device))
  else
    device:try_update_metadata({profile = profile_name})
  end
end

function ButtonDeviceConfiguration.update_button_component_map(device, default_endpoint_id, button_eps)
  -- create component mapping on the main profile button endpoints
  table.sort(button_eps)
  local component_map = {}
  component_map["main"] = default_endpoint_id
  for component_num, ep in ipairs(button_eps) do
    if ep ~= default_endpoint_id then
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

  for _, ep in ipairs(ms_eps) do
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

local function profiling_data_still_required(device)
  for _, field in pairs(fields.profiling_data) do
    if device:get_field(field) == nil then
      return true -- data still required if a field is nil
    end
  end
  return false
end

function DeviceConfiguration.match_profile(driver, device)
  if profiling_data_still_required(device) then return end

  local default_endpoint_id = switch_utils.find_default_endpoint(device)
  local updated_profile

  if #embedded_cluster_utils.get_endpoints(device, clusters.ValveConfigurationAndControl.ID) > 0 then
    updated_profile = "water-valve"
    if #embedded_cluster_utils.get_endpoints(device, clusters.ValveConfigurationAndControl.ID,
      {feature_bitmap = clusters.ValveConfigurationAndControl.types.Feature.LEVEL}) > 0 then
      updated_profile = updated_profile .. "-level"
    end
  end

  local server_onoff_ep_ids = device:get_endpoints(clusters.OnOff.ID) -- get_endpoints defaults to return EPs supporting SERVER or BOTH
  if #server_onoff_ep_ids > 0 then
    SwitchDeviceConfiguration.create_child_devices(driver, device, server_onoff_ep_ids, default_endpoint_id)
  end

  if switch_utils.tbl_contains(server_onoff_ep_ids, default_endpoint_id) then
    updated_profile = SwitchDeviceConfiguration.assign_profile_for_onoff_ep(device, default_endpoint_id)
    local generic_profile = function(s) return string.find(updated_profile or "", s, 1, true) end
    if generic_profile("light-color-level") and #device:get_endpoints(clusters.FanControl.ID) > 0 then
      updated_profile = "light-color-level-fan"
    elseif generic_profile("light-level") and #device:get_endpoints(clusters.OccupancySensing.ID) > 0 then
      updated_profile = "light-level-motion"
    elseif generic_profile("light-level-colorTemperature") or generic_profile("light-color-level") then
      -- ignore attempts to dynamically profile light-level-colorTemperature and light-color-level devices for now, since
      -- these may lose fingerprinted Kelvin ranges when dynamically profiled.
      return
    end
  end

  -- initialize the main device card with buttons if applicable
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  if switch_utils.tbl_contains(fields.STATIC_BUTTON_PROFILE_SUPPORTED, #button_eps) then
    ButtonDeviceConfiguration.update_button_profile(device, default_endpoint_id, #button_eps)
    -- All button endpoints found will be added as additional components in the profile containing the default_endpoint_id.
    ButtonDeviceConfiguration.update_button_component_map(device, default_endpoint_id, button_eps)
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