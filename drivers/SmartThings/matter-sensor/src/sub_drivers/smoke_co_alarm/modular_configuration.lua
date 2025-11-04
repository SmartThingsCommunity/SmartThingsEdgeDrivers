local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local sensor_utils = require "sensor_utils.utils"
local version = require "version"
local embedded_cluster_utils = require "sensor_utils.embedded_cluster_utils"
local fields = require "sensor_utils.fields"

if version.api < 10 then
  clusters.CarbonMonoxideConcentrationMeasurement = require "embedded_clusters.CarbonMonoxideConcentrationMeasurement"
  clusters.SmokeCoAlarm = require "embedded_clusters.SmokeCoAlarm"
end

-- MATCH MODULAR PROFILE FUNCTION
return function(device, battery_supported)
  local enabled_optional_component_capability_pairs = {}
  local main_component_capabilities = {}
  local updated_profile_name = "co-alarm-modular"
  for _, ep_info in (device.endpoints) do
    if sensor_utils.primary_device_type(ep_info) == fields.DEVICE_TYPE_ID.SMOKE_CO_ALARM then
      for _, cluster_info in ipairs(ep_info.clusters) do
        if cluster_info.ID == clusters.SmokeCoAlarm.ID then
          if clusters.SmokeCoAlarm.are_features_supported(clusters.SmokeCoAlarm.types.Feature.SMOKE_ALARM, cluster_info.feature_map) then
            updated_profile_name = "smoke-alarm-modular"
            table.insert(main_component_capabilities, capabilities.smokeDetector.ID)
          end
          if clusters.SmokeCoAlarm.are_features_supported(clusters.SmokeCoAlarm.types.Feature.CO_ALARM, cluster_info.feature_map) then
            table.insert(main_component_capabilities, capabilities.carbonMonoxideDetector.ID)
          end
        elseif cluster_info.ID == clusters.CarbonMonoxideConcentrationMeasurement.ID then
          if clusters.CarbonMonoxideConcentrationMeasurement.are_features_supported(clusters.CarbonMonoxideConcentrationMeasurement.types.Feature.NUMERIC_MEASUREMENT, cluster_info.feature_map) then
            table.insert(main_component_capabilities, capabilities.carbonMonoxideMeasurement.ID)
          end
          if clusters.CarbonMonoxideConcentrationMeasurement.are_features_supported(clusters.CarbonMonoxideConcentrationMeasurement.types.Feature.LEVEL_INDICATION, cluster_info.feature_map) then
            table.insert(main_component_capabilities, capabilities.carbonMonoxideHealthConcern.ID)
          end
        elseif cluster_info.ID == clusters.TemperatureMeasurement.ID then
          table.insert(main_component_capabilities, capabilities.temperatureMeasurement.ID)
        elseif cluster_info.ID == clusters.RelativeHumidityMeasurement.ID then
          table.insert(main_component_capabilities, capabilities.relativeHumidityMeasurement.ID)
        end
      end
    end
  end

  if battery_supported == fields.battery_support.BATTERY_LEVEL then
    table.insert(main_component_capabilities, capabilities.batteryLevel.ID)
  elseif battery_supported == fields.battery_support.BATTERY_PERCENTAGE then
    table.insert(main_component_capabilities, capabilities.battery.ID)
  end

  table.insert(enabled_optional_component_capability_pairs, {"main", main_component_capabilities})
  device:try_update_metadata({profile = updated_profile_name, optional_component_capabilities = enabled_optional_component_capability_pairs})
  -- device:set_field(MODULAR_PROFILE_UPDATED, true)
end
