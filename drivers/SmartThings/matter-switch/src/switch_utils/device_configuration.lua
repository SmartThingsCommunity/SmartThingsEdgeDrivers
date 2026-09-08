-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local version = require "version"
local fields = require "switch_utils.fields"
local switch_utils = require "switch_utils.utils"
local embedded_cluster_utils = require "switch_utils.embedded_cluster_utils"
local update_metadata_request = require "switch_utils.update_metadata_request"

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded_clusters.ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "embedded_clusters.ElectricalPowerMeasurement"
  clusters.ValveConfigurationAndControl = require "embedded_clusters.ValveConfigurationAndControl"
end

-- Catch nil elements errors gracefully without receiving a coroutine error
if version.api < 21 then
  clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct = require "embedded_clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct"
end

local DeviceConfiguration = {}
local ChildConfiguration = {}
local SwitchDeviceConfiguration = {}
local ButtonDeviceConfiguration = {}
local FanDeviceConfiguration = {}
local ValveDeviceConfiguration = {}

function ChildConfiguration.create_or_update_child_devices(driver, device, server_cluster_ep_ids, default_endpoint_id, assign_profile_fn)
  if #server_cluster_ep_ids == 1 and server_cluster_ep_ids[1] == default_endpoint_id then -- no children will be created
    return
  end

  table.sort(server_cluster_ep_ids)
  for device_num, ep_id in ipairs(server_cluster_ep_ids) do
    if ep_id ~= default_endpoint_id then -- don't create a child device that maps to the main endpoint
      local label_and_name = string.format("%s %d", device.label, device_num)
      local child_metadata = assign_profile_fn(device, ep_id, true)
      local existing_child_device = device:get_field(fields.IS_PARENT_CHILD_DEVICE) and switch_utils.find_child(device, ep_id)
      if not existing_child_device then
        device.log.info_with({hub_logs=true}, string.format("Creating child device for endpoint %d with profile %s", ep_id, child_metadata.profile))
        driver:try_create_device({
          type = "EDGE_CHILD",
          label = label_and_name,
          profile = child_metadata.profile,
          parent_device_id = device.id,
          parent_assigned_child_key = string.format("%d", ep_id),
          vendor_provided_label = label_and_name
        })
      else
        existing_child_device:try_update_metadata(child_metadata:format_request())
      end
    end
  end

  -- Persist so that the find_child function is always set on each driver init.
  device:set_field(fields.IS_PARENT_CHILD_DEVICE, true, {persist = true})
  device:set_find_child(switch_utils.find_child)
end

function FanDeviceConfiguration.assign_profile_for_fan_ep(device, server_fan_ep_id)
  local ep_info = switch_utils.get_endpoint_info(device, server_fan_ep_id)
  local fan_cluster_info = switch_utils.find_cluster_on_ep(ep_info, clusters.FanControl.ID) or {}
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

  return update_metadata_request.init()
    :add_profile("fan-modular")
    :add_capabilities_to_component("main", main_component_capabilities)
end

function SwitchDeviceConfiguration.assign_profile_for_onoff_ep(device, server_onoff_ep_id, is_child_device)
  local ep_info = switch_utils.get_endpoint_info(device, server_onoff_ep_id)

  -- per spec, the Switch device types support OnOff as CLIENT, though some vendors break spec and support it as SERVER.
  local primary_dt_id = switch_utils.find_max_subset_device_type(ep_info, fields.DEVICE_TYPE_ID.LIGHT)
    or switch_utils.find_max_subset_device_type(ep_info, fields.DEVICE_TYPE_ID.SWITCH)
    or switch_utils.find_primary_device_type(ep_info)

  local generic_profile = fields.device_type_profile_map[primary_dt_id]

  local static_electrical_tags = switch_utils.get_field_for_endpoint(device, fields.ELECTRICAL_TAGS, server_onoff_ep_id)
  if type(static_electrical_tags) == "string" then
    -- if no associated profile is found for the device type and static electrical tags are available, use "plug-binary" as a fallback
    generic_profile = generic_profile or "plug-binary"
    -- profiles like 'light-binary' and 'plug-binary' should drop the '-binary' and become 'light-power', 'plug-energy-powerConsumption', etc.
    generic_profile = string.gsub(generic_profile, "-binary", "") .. static_electrical_tags
  end

  if is_child_device and generic_profile == switch_utils.get_product_override_field(device, "initial_profile") then
    generic_profile = switch_utils.get_product_override_field(device, "target_profile") or generic_profile
  end

  -- if no supported device type is found, use switch-binary as a generic "OnOff EP" profile
  return update_metadata_request.init():add_profile(generic_profile or "switch-binary")
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

--- Assigns a profile for the Generic Switch (button) endpoints of a device, and maps
--- those endpoints to the components of that profile.
---
--- Button endpoints are generally handled by the modular "button-modular" profile, which
--- enables a button capability on the "main" component and on as many "buttonN" components
--- as the device has additional button endpoints. Devices whose presentation cannot be
--- expressed by the modular profile (combination dimmable light/button devices, and devices
--- with vendor specific preferences or presentation) remain statically profiled.
---
--- @param device any a Matter device object
--- @param default_endpoint_id number the endpoint mapped to the "main" component
--- @param button_ep_ids table the button endpoint ids to profile, from supported_button_eps
--- @return table|nil update_metadata_request nil if no profile is available for these button endpoints
function ButtonDeviceConfiguration.assign_profile_for_button_eps(device, default_endpoint_id, button_ep_ids)
  local static_profile
  if switch_utils.get_product_override_field(device, "is_climate_sensor_w100") then
    static_profile = "3-button-battery-temperature-humidity"
  elseif switch_utils.get_product_override_field(device, "is_ikea_dual_button") then
    static_profile = "ikea-2-button-battery"
  elseif switch_utils.device_type_supports_button_switch_combination(device, default_endpoint_id) then
    if not switch_utils.tbl_contains(fields.STATIC_BUTTON_SWITCH_PROFILE_SUPPORTED, #button_ep_ids) then
      device.log.warn_with({hub_logs=true}, string.format(
        "No light/button profile available for a device with %d button endpoints", #button_ep_ids))
      return nil
    end
    -- remove the "1-" in a device with 1 button ep, e.g. "light-level-1-button" -> "light-level-button"
    static_profile = "light-level-" .. string.gsub(#button_ep_ids .. "-button", "^1%-", "")
  end

  if static_profile then
    ButtonDeviceConfiguration.update_button_component_map(device, default_endpoint_id, button_ep_ids)
    return update_metadata_request.init():add_profile(static_profile)
  end

  local component_map = ButtonDeviceConfiguration.update_button_component_map(device, default_endpoint_id, button_ep_ids, true)
  local updated_metadata = update_metadata_request.init():add_profile("button-modular")
  local main_component_capabilities = {}

  local battery_support = device:get_field(fields.profiling_data.BATTERY_SUPPORT)
  if battery_support == fields.battery_support.BATTERY_PERCENTAGE then
    table.insert(main_component_capabilities, capabilities.battery.ID)
  elseif battery_support == fields.battery_support.BATTERY_LEVEL then
    table.insert(main_component_capabilities, capabilities.batteryLevel.ID)
  end
  if #device:get_endpoints(clusters.OccupancySensing.ID) > 0 then
    table.insert(main_component_capabilities, capabilities.motionSensor.ID)
  end
  updated_metadata:add_capabilities_to_component("main", main_component_capabilities)

  -- iterate by component number rather than over the map itself to keep a stable ordering
  for component_num = 1, #button_ep_ids do
    if component_map["button" .. component_num] then
      updated_metadata:add_capabilities_to_component("button" .. component_num, {capabilities.button.ID})
    end
  end

  return updated_metadata
end

--- Returns the button endpoints of a device that the modular button profile has components for,
--- sorted by endpoint id. A device reporting more button endpoints than there are components to
--- hold them is profiled with as many of them as will fit, rather than losing button support entirely.
---
--- @param device any a Matter device object
--- @param button_ep_ids table the endpoint ids of every momentary switch endpoint
--- @return table the endpoint ids that can be mapped to a component
function ButtonDeviceConfiguration.supported_button_eps(device, button_ep_ids)
  table.sort(button_ep_ids)
  if #button_ep_ids <= fields.MAX_BUTTON_EPS then
    return button_ep_ids
  end

  device.log.warn_with({hub_logs=true}, string.format(
    "Device reports %d button endpoints, only the first %d will be supported", #button_ep_ids, fields.MAX_BUTTON_EPS))
  local supported_button_ep_ids = {}
  for component_num = 1, fields.MAX_BUTTON_EPS do
    table.insert(supported_button_ep_ids, button_ep_ids[component_num])
  end
  return supported_button_ep_ids
end

--- Creates the component mapping for the button endpoints of a device. The endpoint matching
--- default_endpoint_id maps to "main", and every other button endpoint maps to a "buttonN"
--- component, where N is the position of that endpoint in the sorted list of button endpoints.
---
--- @param always_index_components boolean|nil when falsey, a lone button endpoint that is not the
--- default endpoint maps to the unindexed "button" component of the static light-level-button profile.
--- @return table component_map the map that was set on the device
function ButtonDeviceConfiguration.update_button_component_map(device, default_endpoint_id, button_eps, always_index_components)
  -- create component mapping on the main profile button endpoints
  table.sort(button_eps)
  local component_map = {}
  component_map["main"] = default_endpoint_id
  for component_num, ep in ipairs(button_eps) do
    if ep ~= default_endpoint_id then
      local button_component = "button"
      if always_index_components or #button_eps > 1 then
        button_component = button_component .. component_num
      end
      component_map[button_component] = ep
    end
  end
  device:set_field(fields.COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
  return component_map
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
    else
      device.log.info_with({hub_logs=true}, string.format("Component not found for generic switch endpoint %d. Skipping Supported Value configuration", ep))
    end
  end
end

function ValveDeviceConfiguration.assign_profile_for_irrigation_system_ep(device, irrigation_system_ep_id, is_child_device)
  local updated_metadata = update_metadata_request.init():add_profile("irrigation-system")
  local main_component_capabilities = {}

  local valve_ep_ids = switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.WATER_VALVE)
  table.sort(valve_ep_ids)
  local supports_level = switch_utils.find_cluster_on_ep(
    switch_utils.get_endpoint_info(device, is_child_device and irrigation_system_ep_id or valve_ep_ids[1]),
    clusters.ValveConfigurationAndControl.ID,
    {feature_bitmap = clusters.ValveConfigurationAndControl.types.Feature.LEVEL}
  )
  if supports_level then
    table.insert(main_component_capabilities, capabilities.level.ID)
  end

  if is_child_device then
    return updated_metadata:add_capabilities_to_component("main", main_component_capabilities)
  end

  local irrigation_system_ep_info = switch_utils.get_endpoint_info(device, irrigation_system_ep_id)
  if switch_utils.find_cluster_on_ep(irrigation_system_ep_info, clusters.FlowMeasurement.ID) then
    table.insert(main_component_capabilities, capabilities.flowMeasurement.ID)
  end
  if switch_utils.find_cluster_on_ep(irrigation_system_ep_info, clusters.OperationalState.ID) then
    table.insert(main_component_capabilities, capabilities.operationalState.ID)
  end

  return updated_metadata:add_capabilities_to_component("main", main_component_capabilities)
end


-- [[ PROFILE MATCHING AND CONFIGURATIONS ]] --

function DeviceConfiguration.match_child_profile(driver, device)
  local parent_device = device:get_parent_device()
  local irrigation_system_ep_ids = switch_utils.get_endpoints_by_device_type(
    parent_device,
    fields.DEVICE_TYPE_ID.IRRIGATION_SYSTEM
  )
  if #irrigation_system_ep_ids > 0 then
    ChildConfiguration.create_or_update_child_devices(
      driver,
      parent_device,
      {device:get_endpoint()},
      nil,
      ValveDeviceConfiguration.assign_profile_for_irrigation_system_ep
    )
  end
end

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
  local updated_metadata = update_metadata_request.init()

  local server_onoff_ep_ids = device:get_endpoints(clusters.OnOff.ID) -- get_endpoints defaults to return EPs supporting SERVER or BOTH
  if #server_onoff_ep_ids > 0 then
    ChildConfiguration.create_or_update_child_devices(driver, device, server_onoff_ep_ids, default_endpoint_id, SwitchDeviceConfiguration.assign_profile_for_onoff_ep)
  end

  if switch_utils.tbl_contains(server_onoff_ep_ids, default_endpoint_id) then
    updated_metadata = SwitchDeviceConfiguration.assign_profile_for_onoff_ep(device, default_endpoint_id)
    local onoff_profile = updated_metadata.profile
    local generic_profile = function(s) return string.find(onoff_profile or "", s, 1, true) end
    if generic_profile("light-level") and #device:get_endpoints(clusters.OccupancySensing.ID) > 0 then
      updated_metadata:add_profile(switch_utils.get_product_override_field(device, "target_profile") or "light-level-motion")
    elseif switch_utils.check_switch_category_vendor_overrides(device) then
      -- check whether the overwrite should be over "plug" or "light" based on the current profile
      local overwrite_category = string.find(onoff_profile, "plug") and "plug" or "light"
      updated_metadata:add_profile(string.gsub(onoff_profile, overwrite_category, "switch"))
    elseif generic_profile("light-level-colorTemperature") or generic_profile("light-color-level") then
      -- ignore attempts to dynamically profile light-level-colorTemperature and light-color-level devices for now, since
      -- these may lose fingerprinted Kelvin ranges when dynamically profiled.
      return
    end
  end

  local irrigation_system_ep_ids = switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.IRRIGATION_SYSTEM)
  local valve_ep_ids = switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.WATER_VALVE)
  if #irrigation_system_ep_ids > 0 then
    updated_metadata = ValveDeviceConfiguration.assign_profile_for_irrigation_system_ep(device, irrigation_system_ep_ids[1], false)
    ChildConfiguration.create_or_update_child_devices(driver, device, valve_ep_ids, default_endpoint_id, ValveDeviceConfiguration.assign_profile_for_irrigation_system_ep)
  elseif #valve_ep_ids > 0 then
    local valve_profile = "water-valve"
    if #embedded_cluster_utils.get_endpoints(device, clusters.ValveConfigurationAndControl.ID,
      {feature_bitmap = clusters.ValveConfigurationAndControl.types.Feature.LEVEL}) > 0 then
      valve_profile = valve_profile .. "-level"
    end
    updated_metadata = update_metadata_request.init():add_profile(valve_profile)
  end

  if #switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.FAN) > 0 then
    updated_metadata = FanDeviceConfiguration.assign_profile_for_fan_ep(device, default_endpoint_id)
  end

  -- initialize the main device card with buttons if applicable
  local momentary_switch_ep_ids = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  if #momentary_switch_ep_ids > 0 then
    -- All supported button endpoints will be added as additional components in the profile containing the default_endpoint_id.
    local button_ep_ids = ButtonDeviceConfiguration.supported_button_eps(device, momentary_switch_ep_ids)
    local button_metadata = ButtonDeviceConfiguration.assign_profile_for_button_eps(device, default_endpoint_id, button_ep_ids)
    if button_metadata then
      updated_metadata = button_metadata
      ButtonDeviceConfiguration.configure_buttons(device, button_ep_ids)
    end
  end

  device:try_update_metadata(updated_metadata:format_request())
end

return {
  ButtonCfg = ButtonDeviceConfiguration,
  ChildCfg = ChildConfiguration,
  DeviceCfg = DeviceConfiguration,
  SwitchCfg = SwitchDeviceConfiguration,
  ValveCfg = ValveDeviceConfiguration
}
