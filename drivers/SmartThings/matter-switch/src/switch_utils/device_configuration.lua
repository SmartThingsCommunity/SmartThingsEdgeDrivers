-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local version = require "version"
local fields = require "switch_utils.fields"
local switch_utils = require "switch_utils.utils"
local embedded_cluster_utils = require "switch_utils.embedded_cluster_utils"

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded_clusters.ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "embedded_clusters.ElectricalPowerMeasurement"
  clusters.ValveConfigurationAndControl = require "embedded_clusters.ValveConfigurationAndControl"
end

local DeviceConfiguration = {}
local ChildConfiguration = {}
local SwitchDeviceConfiguration = {}
local ButtonDeviceConfiguration = {}
local FanDeviceConfiguration = {}

function ChildConfiguration.create_or_update_child_devices(driver, device, server_cluster_ep_ids, default_endpoint_id, assign_profile_fn)
  if #server_cluster_ep_ids == 1 and server_cluster_ep_ids[1] == default_endpoint_id then -- no children will be created
   return
  end

  table.sort(server_cluster_ep_ids)
  for device_num, ep_id in ipairs(server_cluster_ep_ids) do
    if ep_id ~= default_endpoint_id then -- don't create a child device that maps to the main endpoint
      local label_and_name = string.format("%s %d", device.label, device_num)
      local child_profile, _ = assign_profile_fn(device, ep_id, true)
      local existing_child_device = device:get_field(fields.IS_PARENT_CHILD_DEVICE) and switch_utils.find_child(device, ep_id)
      if not existing_child_device then
        driver:try_create_device({
          type = "EDGE_CHILD",
          label = label_and_name,
          profile = child_profile,
          parent_device_id = device.id,
          parent_assigned_child_key = string.format("%d", ep_id),
          vendor_provided_label = label_and_name
        })
      else
        existing_child_device:try_update_metadata({
          profile = child_profile
        })
      end
    end
  end

  -- Persist so that the find_child function is always set on each driver init.
  device:set_field(fields.IS_PARENT_CHILD_DEVICE, true, {persist = true})
  device:set_find_child(switch_utils.find_child)
end

function FanDeviceConfiguration.assign_profile_for_fan_ep(device, server_fan_ep_id)
  local ep_info = switch_utils.get_endpoint_info(device, server_fan_ep_id)
  local fan_cluster_info = switch_utils.find_cluster_on_ep(ep_info, clusters.FanControl.ID)
  local optional_supported_component_capabilities = {}
  local main_component_capabilities = {}

  if clusters.FanControl.are_features_supported(clusters.FanControl.types.Feature.MULTI_SPEED, fan_cluster_info.feature_map) then
    table.insert(main_component_capabilities, capabilities.fanSpeedPercent.ID)
    -- only fanMode can trigger AUTO, so a multi-speed fan still requires this capability if it supports AUTO
    if clusters.FanControl.are_features_supported(clusters.FanControl.types.Feature.AUTO, fan_cluster_info.feature_map) then
      table.insert(main_component_capabilities, capabilities.fanMode.ID)
    end
  else -- MULTI_SPEED is not supported
    table.insert(main_component_capabilities, capabilities.fanMode.ID)
  end

  table.insert(optional_supported_component_capabilities, {"main", main_component_capabilities})
  return "fan-modular", optional_supported_component_capabilities
end


function SwitchDeviceConfiguration.assign_profile_for_onoff_ep(device, server_onoff_ep_id, is_child_device)
  local ep_info = switch_utils.get_endpoint_info(device, server_onoff_ep_id)

  -- per spec, the Switch device types support OnOff as CLIENT, though some vendors break spec and support it as SERVER.
  local primary_dt_id = switch_utils.find_max_subset_device_type(ep_info, fields.DEVICE_TYPE_ID.LIGHT)
    or switch_utils.find_max_subset_device_type(ep_info, fields.DEVICE_TYPE_ID.SWITCH)
    or switch_utils.find_primary_device_type(ep_info)

  local generic_profile = fields.device_type_profile_map[primary_dt_id]

  local static_electrical_tags = switch_utils.get_field_for_endpoint(device, fields.ELECTRICAL_TAGS, server_onoff_ep_id)
  if static_electrical_tags ~= nil then
    -- profiles like 'light-binary' and 'plug-binary' should drop the '-binary' and become 'light-power', 'plug-energy-powerConsumption', etc.
    generic_profile = string.gsub(generic_profile, "-binary", "") .. static_electrical_tags
  end

  if is_child_device and generic_profile == switch_utils.get_product_override_field(device, "initial_profile") then
    generic_profile = switch_utils.get_product_override_field(device, "target_profile") or generic_profile
  end

  -- if no supported device type is found, return switch-binary as a generic "OnOff EP" profile
  return generic_profile or "switch-binary"
end

-- Per the spec, these attributes are "meant to be changed only during commissioning."
function SwitchDeviceConfiguration.set_device_control_options(device)
  for _, ep in ipairs(device.endpoints) do
    -- before the Matter 1.3 lua libs update (HUB FW 54), OptionsBitmap was defined as LevelControlOptions
    if switch_utils.find_cluster_on_ep(ep, clusters.LevelControl.ID) then
      device:send(clusters.LevelControl.attributes.Options:write(device, ep.endpoint_id, clusters.LevelControl.types.LevelControlOptions.EXECUTE_IF_OFF))
    end
    -- before the Matter 1.4 lua libs update (HUB FW 56), there was no OptionsBitmap type defined
    if switch_utils.find_cluster_on_ep(ep, clusters.ColorControl.ID) then
      local excute_if_off_bit = clusters.ColorControl.types.OptionsBitmap and clusters.ColorControl.types.OptionsBitmap.EXECUTE_IF_OFF or 0x0001
      device:send(clusters.ColorControl.attributes.Options:write(device, ep.endpoint_id, excute_if_off_bit))
    end
  end
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
  local battery_support = device:get_field(fields.profiling_data.BATTERY_SUPPORT)
  if battery_support == fields.battery_support.BATTERY_PERCENTAGE then
    profile_name = profile_name .. "-battery"
  elseif battery_support == fields.battery_support.BATTERY_LEVEL then
    profile_name = profile_name .. "-batteryLevel"
  end
  if switch_utils.get_product_override_field(device, "is_climate_sensor_w100") then
    profile_name = "3-button-battery-temperature-humidity"
  end
  if switch_utils.get_product_override_field(device, "is_ikea_dual_button") then
    profile_name = "ikea-2-button-battery"
  end
  return profile_name
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


function ButtonDeviceConfiguration.configure_buttons(device, momentary_switch_ep_ids)
  local msr_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_RELEASE})
  local msl_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS})
  local msm_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS})

  for _, ep in ipairs(momentary_switch_ep_ids or {}) do
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
  local optional_component_capabilities
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
    ChildConfiguration.create_or_update_child_devices(driver, device, server_onoff_ep_ids, default_endpoint_id, SwitchDeviceConfiguration.assign_profile_for_onoff_ep)
  end

  if switch_utils.tbl_contains(server_onoff_ep_ids, default_endpoint_id) then
    updated_profile = SwitchDeviceConfiguration.assign_profile_for_onoff_ep(device, default_endpoint_id)
    local generic_profile = function(s) return string.find(updated_profile or "", s, 1, true) end
    if generic_profile("light-level") and #device:get_endpoints(clusters.OccupancySensing.ID) > 0 then
      updated_profile = "light-level-motion"
    elseif switch_utils.check_switch_category_vendor_overrides(device) then
      -- check whether the overwrite should be over "plug" or "light" based on the current profile
      local overwrite_category = string.find(updated_profile, "plug") and "plug" or "light"
      updated_profile = string.gsub(updated_profile, overwrite_category, "switch")
    elseif generic_profile("light-level-colorTemperature") or generic_profile("light-color-level") then
      -- ignore attempts to dynamically profile light-level-colorTemperature and light-color-level devices for now, since
      -- these may lose fingerprinted Kelvin ranges when dynamically profiled.
      return
    end
  end

  local fan_device_type_ep_ids = switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.FAN)
  if #fan_device_type_ep_ids > 0 then
    updated_profile, optional_component_capabilities = FanDeviceConfiguration.assign_profile_for_fan_ep(device, default_endpoint_id)
  end

  -- initialize the main device card with buttons if applicable
  local momentary_switch_ep_ids = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  if switch_utils.tbl_contains(fields.STATIC_BUTTON_PROFILE_SUPPORTED, #momentary_switch_ep_ids) then
    updated_profile = ButtonDeviceConfiguration.update_button_profile(device, default_endpoint_id, #momentary_switch_ep_ids)
    -- All button endpoints found will be added as additional components in the profile containing the default_endpoint_id.
    ButtonDeviceConfiguration.update_button_component_map(device, default_endpoint_id, momentary_switch_ep_ids)
    ButtonDeviceConfiguration.configure_buttons(device, momentary_switch_ep_ids)
  end

  device:try_update_metadata({ profile = updated_profile, optional_component_capabilities = optional_component_capabilities })
end

return {
  DeviceCfg = DeviceConfiguration,
  SwitchCfg = SwitchDeviceConfiguration,
  ButtonCfg = ButtonDeviceConfiguration
}
