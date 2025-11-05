-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "sensor_utils.embedded_cluster_utils"
local fields = require "sub_drivers.air_quality_sensor.fields"
local sensor_utils = require "sensor_utils.utils"

local LegacyDeviceConfiguration = {}

local function set_supported_health_concern_values(device, setter_function, cluster, cluster_ep)
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

function LegacyDeviceConfiguration.create_level_measurement_profile(device)
  local meas_name, level_name = "", ""
  for _, cap in ipairs(fields.CONCENTRATION_MEASUREMENT_PROFILE_ORDERING) do
    local cap_id = cap.ID
    local cluster = fields.CONCENTRATION_MEASUREMENT_MAP[cap][2]
    -- capability describes either a HealthConcern or Measurement/Sensor
    if (cap_id:match("HealthConcern$")) then
      local attr_eps = embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.LEVEL_INDICATION })
      if #attr_eps > 0 then
        level_name = level_name .. fields.CONCENTRATION_MEASUREMENT_MAP[cap][1]
        set_supported_health_concern_values(device, fields.CONCENTRATION_MEASUREMENT_MAP[cap][3], cluster, attr_eps[1])
      end
    elseif (cap_id:match("Measurement$") or cap_id:match("Sensor$")) then
      local attr_eps = embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.NUMERIC_MEASUREMENT })
      if #attr_eps > 0 then
        meas_name = meas_name .. fields.CONCENTRATION_MEASUREMENT_MAP[cap][1]
      end
    end
  end
  return meas_name, level_name
end

-- MATCH STATIC PROFILE
function LegacyDeviceConfiguration.match_profile(device)
  local temp_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureMeasurement.ID)
  local humidity_eps = embedded_cluster_utils.get_endpoints(device, clusters.RelativeHumidityMeasurement.ID)

  local profile_name = "aqs"
  local aq_eps = embedded_cluster_utils.get_endpoints(device, clusters.AirQuality.ID)
  set_supported_health_concern_values(device, capabilities.airQualityHealthConcern.supportedAirQualityValues, clusters.AirQuality, aq_eps[1])

  if #temp_eps > 0 then
    profile_name = profile_name .. "-temp"
  end
  if #humidity_eps > 0 then
    profile_name = profile_name .. "-humidity"
  end

  local meas_name, level_name = LegacyDeviceConfiguration.create_level_measurement_profile(device)

  -- If all endpoints are supported, use '-all' in the profile name so that it
  -- remains under the profile name character limit
  if level_name == "-co-co2-no2-ozone-ch2o-pm1-pm25-pm10-radon-tvoc" then
    level_name = "-all"
  end
  if level_name ~= "" then
    profile_name = profile_name .. level_name .. "-level"
  end

  -- If all endpoints are supported, use '-all' in the profile name so that it
  -- remains under the profile name character limit
  if meas_name == "-co-co2-no2-ozone-ch2o-pm1-pm25-pm10-radon-tvoc" then
    meas_name = "-all"
  end
  if meas_name ~= "" then
    profile_name = profile_name .. meas_name .. "-meas"
  end

  if not sensor_utils.tbl_contains(fields.supported_profiles, profile_name) then
    device.log.warn_with({hub_logs=true}, string.format("No matching profile for device. Tried to use profile %s", profile_name))

    local function meas_find(sub_name)
      return string.match(meas_name, sub_name) ~= nil
    end

    -- try to best match to existing profiles
    -- these checks, meas_find("co%-") and meas_find("co$"), match the string to co and NOT co2.
    if meas_find("co%-") or meas_find("co$") or meas_find("no2") or meas_find("ozone") or meas_find("ch2o") or
      meas_find("pm1") or meas_find("pm10") or meas_find("radon") then
      profile_name = "aqs-temp-humidity-all-meas"
    elseif #humidity_eps > 0 or #temp_eps > 0 or meas_find("co2") or meas_find("pm25") or meas_find("tvoc") then
      profile_name = "aqs-temp-humidity-co2-pm25-tvoc-meas"
    else
      -- device only supports air quality at this point
      profile_name = "aqs"
    end
  end
  device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s", profile_name))
  device:try_update_metadata({profile = profile_name})
end

return LegacyDeviceConfiguration