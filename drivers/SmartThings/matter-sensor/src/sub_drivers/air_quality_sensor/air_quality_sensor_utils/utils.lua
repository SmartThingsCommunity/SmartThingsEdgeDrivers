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

--- Deeply compare two values.
--- Handles metatables. Optionally handles cycles and function ignoring.
---
--- @param a any
--- @param b any
--- @param opts table|nil { ignore_functions = boolean, track_cycles = boolean }
--- @param seen table|nil
--- @return boolean
function AirQualitySensorUtils.deep_equals(a, b, opts, seen)
  if a == b then return true end -- same object
  if type(a) ~= type(b) then return false end -- different type
  if type(a) == "function" and opts and opts.ignore_functions then return true end
  if type(a) ~= "table" then return false end -- same type but not table, thus was already compared

  -- check for cycles in table references and preserve reference topology.
  if opts and opts.track_cycles then
    seen = seen or { a_to_b = {}, b_to_a = {} }
    if seen.a_to_b[a] ~= nil then return seen.a_to_b[a] == b end
    if seen.b_to_a[b] ~= nil then return seen.b_to_a[b] == a end
    seen.a_to_b[a] = b
    seen.b_to_a[b] = a
  end

  -- Compare keys/values from a
  for k, v in next, a do
    if not AirQualitySensorUtils.deep_equals(v, rawget(b, k), opts, seen) then
      return false
    end
  end

  -- Ensure b doesn't have extra keys
  for k in next, b do
    if rawget(a, k) == nil then
      return false
    end
  end

  -- Compare metatables
  local mt_a = getmetatable(a)
  local mt_b = getmetatable(b)
  return AirQualitySensorUtils.deep_equals(mt_a, mt_b, opts, seen)
end

return AirQualitySensorUtils
