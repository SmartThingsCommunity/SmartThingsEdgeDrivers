-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "sensor_utils.embedded_cluster_utils"
local fields = require "sensor_utils.fields"
local version = require "version"

if version.api < 11 then
  clusters.BooleanStateConfiguration = require "embedded_clusters.BooleanStateConfiguration"
end

local DeviceConfiguration = {}

function DeviceConfiguration.set_boolean_device_type_per_endpoint(driver, device)
  for _, ep in ipairs(device.endpoints) do
      for _, dt in ipairs(ep.device_types) do
          for dt_name, info in pairs(fields.BOOLEAN_DEVICE_TYPE_INFO) do
              if dt.device_type_id == info.id then
                  device:set_field(dt_name, ep.endpoint_id, { persist = true })
                  device:send(clusters.BooleanStateConfiguration.attributes.SupportedSensitivityLevels:read(device, ep.endpoint_id))
              end
          end
      end
  end
end

local function supports_sensitivity_preferences(device)
  local preference_names = ""
  local sensitivity_eps = embedded_cluster_utils.get_endpoints(device, clusters.BooleanStateConfiguration.ID,
    {feature_bitmap = clusters.BooleanStateConfiguration.types.Feature.SENSITIVITY_LEVEL})
  if sensitivity_eps and #sensitivity_eps > 0 then
    for _, dt_name in ipairs(fields.ORDERED_DEVICE_TYPE_INFO) do
      for _, sensitivity_ep in pairs(sensitivity_eps) do
        if device:get_field(dt_name) == sensitivity_ep and fields.BOOLEAN_DEVICE_TYPE_INFO[dt_name].sensitivity_preference ~= "N/A" then
          preference_names = preference_names .. "-" .. fields.BOOLEAN_DEVICE_TYPE_INFO[dt_name].sensitivity_preference
        end
      end
    end
  end
  return preference_names
end

function DeviceConfiguration.match_profile(driver, device, battery_supported)
  local profile_name = ""

  if device:supports_capability(capabilities.contactSensor) then
    profile_name = profile_name .. "-contact"
  end

  if device:supports_capability(capabilities.illuminanceMeasurement) then
    profile_name = profile_name .. "-illuminance"
  end

  if device:supports_capability(capabilities.temperatureMeasurement) then
    profile_name = profile_name .. "-temperature"
  end

  if device:supports_capability(capabilities.relativeHumidityMeasurement) then
    profile_name = profile_name .. "-humidity"
  end

  if device:supports_capability(capabilities.atmosphericPressureMeasurement) then
    profile_name = profile_name .. "-pressure"
  end

  if device:supports_capability(capabilities.rainSensor) then
    profile_name = profile_name .. "-rain"
  end

  if device:supports_capability(capabilities.temperatureAlarm) then
    profile_name = profile_name .. "-freeze"
  end

  if device:supports_capability(capabilities.waterSensor) then
    profile_name = profile_name .. "-leak"
  end

  if device:supports_capability(capabilities.flowMeasurement) then
    profile_name = profile_name .. "-flow"
  end

  if device:supports_capability(capabilities.button) then
    profile_name = profile_name .. "-button"
  end

  if battery_supported == fields.battery_support.BATTERY_PERCENTAGE then
    profile_name = profile_name .. "-battery"
  elseif battery_supported == fields.battery_support.BATTERY_LEVEL then
    profile_name = profile_name .. "-batteryLevel"
  end

  if device:supports_capability(capabilities.hardwareFault) then
    profile_name = profile_name .. "-fault"
  end

  local concatenated_preferences = supports_sensitivity_preferences(device)
  profile_name = profile_name .. concatenated_preferences

  if device:supports_capability(capabilities.motionSensor) then
    local occupancy_support = "-motion"
    -- If the Occupancy Sensing Cluster’s revision is >= 5 (corresponds to Lua Libs version 13+), and any of the AIR / RAD / RFS / VIS
    -- features are supported by the device, use the presenceSensor capability. Otherwise, use the motionSensor capability. Currently,
    -- presenceSensor only used for devices fingerprinting to the motion-illuminance-temperature-humidity-battery profile.
    if profile_name == "-illuminance-temperature-humidity-battery" and version.api >= 13 then
      if #device:get_endpoints(clusters.OccupancySensing.ID, {feature_bitmap = clusters.OccupancySensing.types.Feature.ACTIVE_INFRARED}) > 0 or
        #device:get_endpoints(clusters.OccupancySensing.ID, {feature_bitmap = clusters.OccupancySensing.types.Feature.RADAR}) > 0 or
        #device:get_endpoints(clusters.OccupancySensing.ID, {feature_bitmap = clusters.OccupancySensing.types.Feature.RF_SENSING}) > 0 or
        #device:get_endpoints(clusters.OccupancySensing.ID, {feature_bitmap = clusters.OccupancySensing.types.Feature.VISION}) then
        occupancy_support = "-presence"
      end
    end
    profile_name = occupancy_support .. profile_name
  end

  -- remove leading "-"
  profile_name = string.sub(profile_name, 2)

  device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
  device:try_update_metadata({profile = profile_name})
end

return DeviceConfiguration