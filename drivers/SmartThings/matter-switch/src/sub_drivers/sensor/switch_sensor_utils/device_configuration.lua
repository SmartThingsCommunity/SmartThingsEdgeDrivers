-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local fields = require "switch_utils.fields"
local switch_utils = require "switch_utils.utils"
local sensor_fields = require "sub_drivers.sensor.switch_sensor_utils.fields"

local SensorDeviceConfiguration = {}

--- Helper function for get_generic_sensor_profile to return the "-sensitivity" profile
--- name tag if a device optionally supports a sensitivity preference. At present, this
--- is only applicable to freeze, leak, and rain sensors
---
--- To be appended onto a generic profile name. Ex. "leak" becomes "leak-sensitivity"
--- @return string "-sensitivity" or "".
local function get_sensitivity_preference_tag(device, ep_id, ep_primary_device_type)
  local ep_info = switch_utils.get_endpoint_info(device, ep_id)
  local applicable_device_types = {
    fields.DEVICE_TYPE_ID.WATER_FREEZE_DETECTOR,
    fields.DEVICE_TYPE_ID.WATER_LEAK_DETECTOR,
    fields.DEVICE_TYPE_ID.RAIN_SENSOR
  }
  return switch_utils.tbl_contains(applicable_device_types, ep_primary_device_type) and
    switch_utils.find_cluster_on_ep(ep_info, clusters.BooleanStateConfiguration.ID,
    {feature_bitmap = clusters.BooleanStateConfiguration.types.Feature.SENSITIVITY_LEVEL}) and
    "-sensitivity" or ""
end

--- Helper function for assign_profile_for_standalone_sensor_ep to return the generic profile
--- name of the endpoint's device type.
---
--- @return string|nil profile or nil if the device type has no supported profile
local function get_generic_sensor_profile(device, ep_id)
  for device_type_id, profile_name in pairs(sensor_fields.DEVICE_TYPE_PROFILE_MAP) do
    if switch_utils.tbl_contains(switch_utils.get_endpoints_by_device_type(device, device_type_id), ep_id) then
      local generic_profile = profile_name .. get_sensitivity_preference_tag(device, ep_id, device_type_id)
      return generic_profile
    end
  end
end

--- Generic profile assignment function for devices that support a single capability.
---
--- @return string|nil profile or nil if the device type has no supported profile
--- @return table component_capabilities defining which capabilities should be enabled on which component
function SensorDeviceConfiguration.assign_profile_for_standalone_sensor_ep(device, sensor_ep_id, is_child_device)
  local main_component = {"main", {}}
  if switch_utils.get_field(device, fields.profiling_data.SENSOR_FAULT_SUPPORTED) then
    switch_utils.enable_optional_capability_on_component(main_component, capabilities.hardwareFault.ID)
  end
  if not is_child_device then
    switch_utils.insert_battery_on_component(device, main_component)
  end
  local generic_profile = get_generic_sensor_profile(device, sensor_ep_id)
  return generic_profile, {main_component}
end

--- Assign profile for motion/occupancy sensor endpoint
---
--- @return string|nil profile or nil if the device type has no supported profile
--- @return table component_capabilities defining which capabilities should be enabled on which component
function SensorDeviceConfiguration.assign_profile_for_occupancy_sensor_ep(device, occupancy_ep_id, is_child_device)
  local main_component = {"main", {}}

  if not is_child_device then
    switch_utils.insert_battery_on_component(device, main_component)
    if #switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.CONTACT_SENSOR) > 0 then
      switch_utils.enable_optional_capability_on_component(main_component, capabilities.contactSensor.ID)
    end
    if #device:get_endpoints(clusters.IlluminanceMeasurement.ID) > 0 then
      switch_utils.enable_optional_capability_on_component(main_component, capabilities.illuminanceMeasurement.ID)
    end
    if #device:get_endpoints(clusters.TemperatureMeasurement.ID) > 0 then
      switch_utils.enable_optional_capability_on_component(main_component, capabilities.temperatureMeasurement.ID)
    end
    if #device:get_endpoints(clusters.RelativeHumidityMeasurement.ID) > 0 then
      switch_utils.enable_optional_capability_on_component(main_component, capabilities.relativeHumidityMeasurement.ID)
    end
  end

  -- Assign base profile as either motion or presence
  local ep_info = switch_utils.get_endpoint_info(device, occupancy_ep_id)
  local f = clusters.OccupancySensing.types.Feature
  local feature_map = switch_utils.find_cluster_on_ep(ep_info, clusters.OccupancySensing.ID)[1].feature_map or 0
  local profile_name = clusters.OccupancySensing.are_features_supported(f.ACTIVE_INFRARED, feature_map) or
       clusters.OccupancySensing.are_features_supported(f.RADAR, feature_map) or
       clusters.OccupancySensing.are_features_supported(f.RF_SENSING, feature_map) or
       clusters.OccupancySensing.are_features_supported(f.VISION, feature_map) and "presence" or "motion"

  return profile_name, {main_component}
end

--- Assign profile for device that supports both temperature and humidity sensor
---
--- @return string|nil profile or nil if the device type has no supported profile
--- @return table component_capabilities defining which capabilities should be enabled on which component
function SensorDeviceConfiguration.assign_profile_for_temp_humidity_sensor_ep(device, ep_id, is_child_device)
  local main_component = {"main", {}}
  if not is_child_device then
    switch_utils.insert_battery_on_component(device, main_component)
  end
  if #device:get_endpoints(clusters.PressureMeasurement.ID) > 0 then
    switch_utils.enable_optional_capability_on_component(main_component, capabilities.atmosphericPressureMeasurement.ID)
  end
  return "temperature-humidity", {main_component}
end

--- Main configuration function to handle sensor endpoints, which should be called from
--- the main driver's match_profile function. Returns information regarding the primary profile and enabled capabilities,
--- and creates child devices per endpoint as needed.
---
--- @param default_endpoint_id number an Endpoint ID of the primary endpoint for the ST implementation of the device
--- @return string|nil profile or nil if the device type has no supported profile
--- @return table component_capabilities defining which capabilities should be enabled on which component
function SensorDeviceConfiguration.configure_sensor_endpoints(driver, device, default_endpoint_id)
  local cfg = require("switch_utils.device_configuration")
  local updated_profile, optional_component_capabilities

  local occupancy_ep_ids = device:get_endpoints(clusters.OccupancySensing.ID)
  local is_occupancy_default = switch_utils.tbl_contains(occupancy_ep_ids, default_endpoint_id)
  if is_occupancy_default then
    updated_profile, optional_component_capabilities = SensorDeviceConfiguration.assign_profile_for_occupancy_sensor_ep(device, default_endpoint_id)
  end

  local temperature_ep_ids = device:get_endpoints(clusters.TemperatureMeasurement.ID)
  local relative_humidity_ep_ids = device:get_endpoints(clusters.RelativeHumidityMeasurement.ID)
  local is_temp_humidity_default = false
  if #temperature_ep_ids > 0 and #relative_humidity_ep_ids > 0 and
    (switch_utils.tbl_contains(temperature_ep_ids, default_endpoint_id) or switch_utils.tbl_contains(relative_humidity_ep_ids, default_endpoint_id)) then
    updated_profile, optional_component_capabilities = SensorDeviceConfiguration.assign_profile_for_temp_humidity_sensor_ep(device, default_endpoint_id)
    is_temp_humidity_default = true
  end

  for device_type_id, _ in pairs(sensor_fields.DEVICE_TYPE_PROFILE_MAP) do
    local sensor_ep_ids = switch_utils.get_endpoints_by_device_type(device, device_type_id)
    if switch_utils.tbl_contains(sensor_ep_ids, default_endpoint_id) then
      updated_profile, optional_component_capabilities = SensorDeviceConfiguration.assign_profile_for_standalone_sensor_ep(device, default_endpoint_id)
    elseif (is_occupancy_default and switch_utils.tbl_contains(sensor_fields.OCCUPANCY_PROFILE_SUPPORTED_DEVICE_TYPES, device_type_id)) or
      (is_temp_humidity_default and switch_utils.tbl_contains(sensor_fields.TEMP_HUMIDITY_PROFILE_SUPPORTED_DEVICE_TYPES, device_type_id)) then
      table.remove(sensor_ep_ids, 1)
    end
    if #sensor_ep_ids > 0 then
      cfg.DeviceCfg.create_or_update_child_devices(driver, device, sensor_ep_ids, default_endpoint_id, SensorDeviceConfiguration.assign_profile_for_standalone_sensor_ep)
    end
  end

  return updated_profile, optional_component_capabilities
end

return SensorDeviceConfiguration
