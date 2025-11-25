-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "sensor_utils.embedded_cluster_utils"
local fields = require "sub_drivers.air_quality_sensor.air_quality_sensor_utils.fields"


local AirQualitySensorUtils = {}

function AirQualitySensorUtils.is_matter_air_quality_sensor(opts, driver, device)
    for _, ep in ipairs(device.endpoints) do
      for _, dt in ipairs(ep.device_types) do
        if dt.device_type_id == fields.AIR_QUALITY_SENSOR_DEVICE_TYPE_ID then
          return true
        end
      end
    end

    return false
  end

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

function AirQualitySensorUtils.set_supported_health_concern_values_helper(device, setter_function, cluster, cluster_ep)
  -- read_datatype_value works since all the healthConcern capabilities' datatypes are equivalent to the one in airQualityHealthConcern
  local read_datatype_value = capabilities.airQualityHealthConcern.airQualityHealthConcern
  local supported_values = {read_datatype_value.unknown.NAME, read_datatype_value.good.NAME, read_datatype_value.unhealthy.NAME}
  if cluster == clusters.AirQuality then
    if #embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.FAIR }) > 0 then
      table.insert(supported_values, 3, read_datatype_value.moderate.NAME)
    end
    if #embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.MODERATE }) > 0 then
      table.insert(supported_values, 4, read_datatype_value.slightlyUnhealthy.NAME)
    end
    if #embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.VERY_POOR }) > 0 then
      table.insert(supported_values, read_datatype_value.veryUnhealthy.NAME)
    end
    if #embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.EXTREMELY_POOR }) > 0 then
      table.insert(supported_values, read_datatype_value.hazardous.NAME)
    end
  else -- ConcentrationMeasurement clusters
    if #embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.MEDIUM_LEVEL }) > 0 then
      table.insert(supported_values, 3, read_datatype_value.moderate.NAME)
    end
    if #embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.CRITICAL_LEVEL }) > 0 then
      table.insert(supported_values, read_datatype_value.hazardous.NAME)
    end
  end
  device:emit_event_for_endpoint(cluster_ep, setter_function(supported_values, { visibility = { displayed = false }}))
end

function AirQualitySensorUtils.set_supported_health_concern_values(device)
  local aqs_eps = embedded_cluster_utils.get_endpoints(device, clusters.AirQuality.ID) or {}
  AirQualitySensorUtils.set_supported_health_concern_values_helper(device, capabilities.airQualityHealthConcern.supportedAirQualityValues, clusters.AirQuality, aqs_eps[1])

  for _, cap in ipairs(fields.CONCENTRATION_MEASUREMENT_PROFILE_ORDERING) do
    local cap_id  = cap.ID
    local cluster = fields.CONCENTRATION_MEASUREMENT_MAP[cap][2]
    -- capability describes either a HealthConcern or Measurement/Sensor
    if (cap_id:match("HealthConcern$")) then
      local attr_eps = embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.LEVEL_INDICATION }) or {}
      if #attr_eps > 0 then
        AirQualitySensorUtils.set_supported_health_concern_values_helper(device, fields.CONCENTRATION_MEASUREMENT_MAP[cap][3], cluster, attr_eps[1])
      end
    end
  end
end

return AirQualitySensorUtils
