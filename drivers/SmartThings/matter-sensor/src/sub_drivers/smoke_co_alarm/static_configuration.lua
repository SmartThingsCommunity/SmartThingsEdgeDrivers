local clusters = require "st.matter.clusters"
local sensor_utils = require "sensor_utils.utils"
local version = require "version"
local embedded_cluster_utils = require "sensor_utils.embedded_cluster_utils"
local fields = require "sensor_utils.fields"

if version.api < 10 then
  clusters.CarbonMonoxideConcentrationMeasurement = require "embedded_clusters.CarbonMonoxideConcentrationMeasurement"
  clusters.SmokeCoAlarm = require "embedded_clusters.SmokeCoAlarm"
end

local supported_profiles =
{
  "co",
  "co-battery",
  "co-comeas",
  "co-comeas-battery",
  "co-comeas-colevel-battery",
  "smoke",
  "smoke-battery",
  "smoke-co-comeas",
  "smoke-co-comeas-battery",
  "smoke-co-temp-humidity-comeas",
  "smoke-co-temp-humidity-comeas-battery"
}

-- MATCH STATIC PROFILE FUNCTION
return function(device, battery_supported)
  local smoke_eps = embedded_cluster_utils.get_endpoints(device, clusters.SmokeCoAlarm.ID, {feature_bitmap = clusters.SmokeCoAlarm.types.Feature.SMOKE_ALARM})
  local co_eps = embedded_cluster_utils.get_endpoints(device, clusters.SmokeCoAlarm.ID, {feature_bitmap = clusters.SmokeCoAlarm.types.Feature.CO_ALARM})
  local temp_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureMeasurement.ID)
  local humidity_eps = embedded_cluster_utils.get_endpoints(device, clusters.RelativeHumidityMeasurement.ID)
  local co_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.CarbonMonoxideConcentrationMeasurement.ID, {feature_bitmap = clusters.CarbonMonoxideConcentrationMeasurement.types.Feature.NUMERIC_MEASUREMENT})
  local co_level_eps = embedded_cluster_utils.get_endpoints(device, clusters.CarbonMonoxideConcentrationMeasurement.ID, {feature_bitmap = clusters.CarbonMonoxideConcentrationMeasurement.types.Feature.LEVEL_INDICATION})

  local profile_name = ""

  -- battery and hardware fault are mandatory
  if #smoke_eps > 0 then
    profile_name = profile_name .. "-smoke"
  end
  if #co_eps > 0 then
    profile_name = profile_name .. "-co"
  end
  if #temp_eps > 0 then
    profile_name = profile_name .. "-temp"
  end
  if #humidity_eps > 0 then
    profile_name = profile_name .. "-humidity"
  end
  if #co_meas_eps > 0 then
    profile_name = profile_name .. "-comeas"
  end
  if #co_level_eps > 0 then
    profile_name = profile_name .. "-colevel"
  end
  if battery_supported == fields.battery_support.BATTERY_PERCENTAGE then
    profile_name = profile_name .. "-battery"
  end

  -- remove leading "-"
  profile_name = string.sub(profile_name, 2)

  if sensor_utils.tbl_contains(supported_profiles, profile_name) then
    device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
  else
    device.log.warn_with({hub_logs=true}, string.format("No matching profile for device. Tried to use profile %s.", profile_name))
    profile_name = ""
    if #smoke_eps > 0 and #co_eps > 0 then
      profile_name = "smoke-co"
    elseif #smoke_eps > 0 and #co_eps == 0 then
      profile_name = "smoke"
    elseif #co_eps > 0 and #smoke_eps == 0 then
      profile_name = "co"
    end
    device.log.info_with({hub_logs=true}, string.format("Using generic device profile %s.", profile_name))
  end
  device:try_update_metadata({profile = profile_name})
end
