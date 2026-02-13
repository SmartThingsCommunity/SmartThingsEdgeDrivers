-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "sensor_utils.embedded_cluster_utils"
local fields = require "sub_drivers.air_quality_sensor.air_quality_sensor_utils.fields"


local AirQualitySensorUtils = {}

function AirQualitySensorUtils.supports_capability_by_id_modular(device, capability, component)
  if not device:get_field(fields.SUPPORTED_COMPONENT_CAPABILITIES) then
    device.log.warn_with({hub_logs = true}, "Device has overriden supports_capability_by_id, but does not have supported capabilities set.")
    return false
  end
  for _, component_capabilities in ipairs(device:get_field(fields.SUPPORTED_COMPONENT_CAPABILITIES)) do
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

local function get_supported_health_concern_values_for_air_quality(device)
  local health_concern_datatype = capabilities.airQualityHealthConcern.airQualityHealthConcern
  local supported_values = {health_concern_datatype.unknown.NAME, health_concern_datatype.good.NAME, health_concern_datatype.unhealthy.NAME}
  if #embedded_cluster_utils.get_endpoints(device, clusters.AirQuality.ID, { feature_bitmap = clusters.AirQuality.types.Feature.FAIR }) > 0 then
    table.insert(supported_values, health_concern_datatype.moderate.NAME)
  end
  if #embedded_cluster_utils.get_endpoints(device, clusters.AirQuality.ID, { feature_bitmap = clusters.AirQuality.types.Feature.MODERATE }) > 0 then
    table.insert(supported_values, health_concern_datatype.slightlyUnhealthy.NAME)
  end
  if #embedded_cluster_utils.get_endpoints(device, clusters.AirQuality.ID, { feature_bitmap = clusters.AirQuality.types.Feature.VERY_POOR }) > 0 then
    table.insert(supported_values, health_concern_datatype.veryUnhealthy.NAME)
  end
  if #embedded_cluster_utils.get_endpoints(device, clusters.AirQuality.ID, { feature_bitmap = clusters.AirQuality.types.Feature.EXTREMELY_POOR }) > 0 then
    table.insert(supported_values, health_concern_datatype.hazardous.NAME)
  end
  return supported_values
end

local function get_supported_health_concern_values_for_concentration_cluster(device, cluster)
  -- note: health_concern_datatype is generic since all the healthConcern capabilities' datatypes are equivalent to those in airQualityHealthConcern
  local health_concern_datatype = capabilities.airQualityHealthConcern.airQualityHealthConcern
  local supported_values = {health_concern_datatype.unknown.NAME, health_concern_datatype.good.NAME, health_concern_datatype.unhealthy.NAME}
  if #embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.MEDIUM_LEVEL }) > 0 then
    table.insert(supported_values, health_concern_datatype.moderate.NAME)
  end
  if #embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.CRITICAL_LEVEL }) > 0 then
    table.insert(supported_values, health_concern_datatype.hazardous.NAME)
  end
  return supported_values
end

function AirQualitySensorUtils.set_supported_health_concern_values(device)
  -- handle AQ Health Concern, since this is a mandatory capability
  local supported_aqs_values = get_supported_health_concern_values_for_air_quality(device)
  local aqs_ep_ids = embedded_cluster_utils.get_endpoints(device, clusters.AirQuality.ID) or {}
  device:emit_event_for_endpoint(aqs_ep_ids[1], capabilities.airQualityHealthConcern.supportedAirQualityValues(supported_aqs_values, { visibility = { displayed = false }}))

  for _, capability in ipairs(fields.CONCENTRATION_MEASUREMENT_PROFILE_ORDERING) do
    -- all of these capabilities are optional, and capabilities stored in this field are for either a HealthConcern or a Measurement/Sensor
    if device:supports_capability_by_id(capability.ID) and capability.ID:match("HealthConcern$") then
      local cluster_info = fields.CONCENTRATION_MEASUREMENT_MAP[capability][2]
      local supported_values_setter = fields.CONCENTRATION_MEASUREMENT_MAP[capability][3]
      local supported_values = get_supported_health_concern_values_for_concentration_cluster(device, cluster_info)
      local cluster_ep_ids = embedded_cluster_utils.get_endpoints(device, cluster_info.ID, { feature_bitmap = cluster_info.types.Feature.LEVEL_INDICATION }) or {} -- cluster associated with the supported capability
      device:emit_event_for_endpoint(cluster_ep_ids[1], supported_values_setter(supported_values, { visibility = { displayed = false }}))
    end
  end
end

function AirQualitySensorUtils.profile_changed(latest_profile, previous_profile)
  if latest_profile.id ~= previous_profile.id then
    return true
  end
  for component_id, synced_component in pairs(latest_profile.components or {}) do
    local prev_component = previous_profile.components[component_id]
    if prev_component == nil then
      return true
    end
    if #synced_component.capabilities ~= #prev_component.capabilities then
      return true
    end
    -- Build a table of capability IDs from the previous component. Then, use this map to check
    -- that all capabilities in the synced component existed in the previous component.
    local prev_cap_ids = {}
    for _, capability in ipairs(prev_component.capabilities or {}) do
      prev_cap_ids[capability.id] = true
    end
    for _, capability in ipairs(synced_component.capabilities or {}) do
      if not prev_cap_ids[capability.id] then
        return true
      end
    end
  end
  return false
end


return AirQualitySensorUtils
