-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local version = require "version"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "thermostat_utils.embedded_cluster_utils"
local fields = require "thermostat_utils.fields"
local thermostat_utils = require "thermostat_utils.utils"

if version.api < 10 then
  clusters.HepaFilterMonitoring = require "embedded_clusters.HepaFilterMonitoring"
  clusters.ActivatedCarbonFilterMonitoring = require "embedded_clusters.ActivatedCarbonFilterMonitoring"
  clusters.AirQuality = require "embedded_clusters.AirQuality"
end

local LegacyConfigurationHelpers = {}

function LegacyConfigurationHelpers.create_level_measurement_profile(device)
  local meas_name, level_name = "", ""
  for _, details in ipairs(fields.AIR_QUALITY_MAP) do
    local cap_id  = details[1]
    local cluster = details[3]
    -- capability describes either a HealthConcern or Measurement/Sensor
    if (cap_id:match("HealthConcern$")) then
      local attr_eps = embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.LEVEL_INDICATION })
      if #attr_eps > 0 then
        level_name = level_name .. details[2]
      end
    elseif (cap_id:match("Measurement$") or cap_id:match("Sensor$")) then
      local attr_eps = embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.NUMERIC_MEASUREMENT })
      if #attr_eps > 0 then
        meas_name = meas_name .. details[2]
      end
    end
  end
  return meas_name, level_name
end

function LegacyConfigurationHelpers.create_air_quality_sensor_profile(device)
  local aqs_eps = embedded_cluster_utils.get_endpoints(device, clusters.AirQuality.ID)
  local profile_name = ""
  if #aqs_eps > 0 then
    profile_name = profile_name .. "-aqs"
  end
  local meas_name, level_name = LegacyConfigurationHelpers.create_level_measurement_profile(device)
  if meas_name ~= "" then
    profile_name = profile_name .. meas_name .. "-meas"
  end
  if level_name ~= "" then
    profile_name = profile_name .. level_name .. "-level"
  end
  return profile_name
end

function LegacyConfigurationHelpers.create_fan_profile(device)
  local fan_eps = device:get_endpoints(clusters.FanControl.ID)
  local wind_eps = device:get_endpoints(clusters.FanControl.ID, {feature_bitmap = clusters.FanControl.types.FanControlFeature.WIND})
  local rock_eps = device:get_endpoints(clusters.FanControl.ID, {feature_bitmap = clusters.FanControl.types.Feature.ROCKING})
  local profile_name = ""
  if #fan_eps > 0 then
    profile_name = profile_name .. "-fan"
  end
  if #rock_eps > 0 then
    profile_name = profile_name .. "-rock"
  end
  if #wind_eps > 0 then
    profile_name = profile_name .. "-wind"
  end
  return profile_name
end

function LegacyConfigurationHelpers.create_air_purifier_profile(device)
  local hepa_filter_eps = embedded_cluster_utils.get_endpoints(device, clusters.HepaFilterMonitoring.ID)
  local ac_filter_eps = embedded_cluster_utils.get_endpoints(device, clusters.ActivatedCarbonFilterMonitoring.ID)
  local fan_eps_seen = false
  local profile_name = "air-purifier"
  if #hepa_filter_eps > 0 then
    profile_name = profile_name .. "-hepa"
  end
  if #ac_filter_eps > 0 then
    profile_name = profile_name .. "-ac"
  end

  -- air purifier profiles include -fan later in the name for historical reasons.
  -- save this information for use at that point.
  local fan_profile = LegacyConfigurationHelpers.create_fan_profile(device)
  if fan_profile ~= "" then
    fan_eps_seen = true
  end
  fan_profile = string.gsub(fan_profile, "-fan", "")
  profile_name = profile_name .. fan_profile

  return profile_name, fan_eps_seen
end

function LegacyConfigurationHelpers.create_thermostat_modes_profile(device)
  local heat_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.HEATING})
  local cool_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.COOLING})

  local thermostat_modes = ""
  if #heat_eps == 0 and #cool_eps == 0 then
    return "No Heating nor Cooling Support"
  elseif #heat_eps > 0 and #cool_eps == 0 then
    thermostat_modes = thermostat_modes .. "-heating-only"
  elseif #cool_eps > 0 and #heat_eps == 0 then
    thermostat_modes = thermostat_modes .. "-cooling-only"
  end
  return thermostat_modes
end


local LegacyDeviceConfiguration = {}

function LegacyDeviceConfiguration.match_profile(device)
  local running_state_supported = device:get_field(fields.profiling_data.THERMOSTAT_RUNNING_STATE_SUPPORT)
  local battery_supported = device:get_field(fields.profiling_data.BATTERY_SUPPORT)

  local thermostat_eps = device:get_endpoints(clusters.Thermostat.ID)
  local humidity_eps = device:get_endpoints(clusters.RelativeHumidityMeasurement.ID)
  local device_type = thermostat_utils.get_device_type(device)
  local profile_name
  if device_type == fields.RAC_DEVICE_TYPE_ID then
    profile_name = "room-air-conditioner"

    if #humidity_eps > 0 then
      profile_name = profile_name .. "-humidity"
    end

    -- Room AC does not support the rocking feature of FanControl.
    local fan_name = LegacyConfigurationHelpers.create_fan_profile(device)
    fan_name = string.gsub(fan_name, "-rock", "")
    profile_name = profile_name .. fan_name

    local thermostat_modes = LegacyConfigurationHelpers.create_thermostat_modes_profile(device)
    if thermostat_modes == "" then
      profile_name = profile_name .. "-heating-cooling"
    else
      device.log.warn_with({hub_logs=true}, "Device does not support both heating and cooling. No matching profile")
      return
    end

    if profile_name == "room-air-conditioner-humidity-fan-wind-heating-cooling" then
      profile_name = "room-air-conditioner"
    end

    if not running_state_supported and profile_name == "room-air-conditioner-fan-heating-cooling" then
      profile_name = profile_name .. "-nostate"
    end

  elseif device_type == fields.FAN_DEVICE_TYPE_ID then
    profile_name = LegacyConfigurationHelpers.create_fan_profile(device)
    -- remove leading "-"
    profile_name = string.sub(profile_name, 2)
    if profile_name == "fan" then
      profile_name = "fan-generic"
    end

  elseif device_type == fields.AP_DEVICE_TYPE_ID then
    local fan_eps_found
    profile_name, fan_eps_found = LegacyConfigurationHelpers.create_air_purifier_profile(device)
    if #thermostat_eps > 0 then
      profile_name = profile_name .. "-thermostat"

      if #humidity_eps > 0 then
        profile_name = profile_name .. "-humidity"
      end

      if fan_eps_found then
        profile_name = profile_name .. "-fan"
      end

      local thermostat_modes = LegacyConfigurationHelpers.create_thermostat_modes_profile(device)
      if thermostat_modes ~= "No Heating nor Cooling Support" then
        profile_name = profile_name .. thermostat_modes
      end

      if not running_state_supported then
        profile_name = profile_name .. "-nostate"
      end

      if battery_supported == fields.battery_support.BATTERY_LEVEL then
        profile_name = profile_name .. "-batteryLevel"
      elseif battery_supported == fields.battery_support.NO_BATTERY then
        profile_name = profile_name .. "-nobattery"
      end
    elseif #device:get_endpoints(clusters.TemperatureMeasurement.ID) > 0 then
      profile_name = profile_name .. "-temperature"

      if #humidity_eps > 0 then
        profile_name = profile_name .. "-humidity"
      end

      if fan_eps_found then
        profile_name = profile_name .. "-fan"
      end
    end
    profile_name = profile_name .. LegacyConfigurationHelpers.create_air_quality_sensor_profile(device)
  elseif device_type == fields.WATER_HEATER_DEVICE_TYPE_ID then
    -- If a Water Heater is composed of Electrical Sensor device type, it must support both ElectricalEnergyMeasurement and
    -- ElectricalPowerMeasurement clusters.
    local electrical_sensor_eps = thermostat_utils.get_endpoints_by_device_type(device, fields.ELECTRICAL_SENSOR_DEVICE_TYPE_ID) or {}
    if #electrical_sensor_eps > 0 then
      profile_name = "water-heater-power-energy-powerConsumption"
    end
  elseif device_type == fields.HEAT_PUMP_DEVICE_TYPE_ID then
    profile_name = "heat-pump"
    local MAX_HEAT_PUMP_THERMOSTAT_COMPONENTS = 2
    for i = 1, math.min(MAX_HEAT_PUMP_THERMOSTAT_COMPONENTS, #thermostat_eps) do
        profile_name = profile_name .. "-thermostat"
        if thermostat_utils.tbl_contains(humidity_eps, thermostat_eps[i]) then
          profile_name = profile_name .. "-humidity"
        end
    end
  elseif #thermostat_eps > 0 then
    profile_name = "thermostat"

    if #humidity_eps > 0 then
      profile_name = profile_name .. "-humidity"
    end

    -- thermostat profiles support neither wind nor rocking FanControl attributes
    local fan_name = LegacyConfigurationHelpers.create_fan_profile(device)
    if fan_name ~= "" then
      profile_name = profile_name .. "-fan"
    end

    local thermostat_modes = LegacyConfigurationHelpers.create_thermostat_modes_profile(device)
    if thermostat_modes == "No Heating nor Cooling Support" then
      device.log.warn_with({hub_logs=true}, "Device does not support either heating or cooling. No matching profile")
      return
    else
      profile_name = profile_name .. thermostat_modes
    end

    if not running_state_supported then
      profile_name = profile_name .. "-nostate"
    end

    if battery_supported == fields.battery_support.BATTERY_LEVEL then
      profile_name = profile_name .. "-batteryLevel"
    elseif battery_supported == fields.battery_support.NO_BATTERY then
      profile_name = profile_name .. "-nobattery"
    end
  else
    device.log.warn_with({hub_logs=true}, "Device type is not supported in thermostat driver")
    return
  end

  if profile_name then
    device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({profile = profile_name})
  end
  -- clear all profiling data fields after profiling is complete.
  for _, field in pairs(fields.profiling_data) do
    device:set_field(field, nil)
  end
end

return LegacyDeviceConfiguration
