-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "thermostat_utils.embedded_cluster_utils"
local version = require "version"
local fields = require "thermostat_utils.fields"
local thermostat_utils = require "thermostat_utils.utils"

if version.api < 10 then
  clusters.HepaFilterMonitoring = require "embedded_clusters.HepaFilterMonitoring"
  clusters.ActivatedCarbonFilterMonitoring = require "embedded_clusters.ActivatedCarbonFilterMonitoring"
end

if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded_clusters.ElectricalEnergyMeasurement"
end

if version.api < 13 then
  clusters.WaterHeaterMode = require "embedded_clusters.WaterHeaterMode"
end

local DeviceConfigurationHelpers = {}

function DeviceConfigurationHelpers.supported_level_measurements(device)
  local measurement_caps, level_caps = {}, {}
  for _, details in ipairs(fields.AIR_QUALITY_MAP) do
    local cap_id  = details[1]
    local cluster = details[3]
    -- capability describes either a HealthConcern or Measurement/Sensor
    if (cap_id:match("HealthConcern$")) then
      local attr_eps = embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.LEVEL_INDICATION })
      if #attr_eps > 0 then
        table.insert(level_caps, cap_id)
      end
    elseif (cap_id:match("Measurement$") or cap_id:match("Sensor$")) then
      local attr_eps = embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.NUMERIC_MEASUREMENT })
      if #attr_eps > 0 then
        table.insert(measurement_caps, cap_id)
      end
    end
  end
  return measurement_caps, level_caps
end

function DeviceConfigurationHelpers.get_thermostat_optional_capabilities(device)
  local heat_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.HEATING})
  local cool_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.COOLING})
  local running_state_supported = device:get_field(fields.profiling_data.THERMOSTAT_RUNNING_STATE_SUPPORT)

  local supported_thermostat_capabilities = {}

  if #heat_eps > 0 then
    table.insert(supported_thermostat_capabilities, capabilities.thermostatHeatingSetpoint.ID)
  end
  if #cool_eps > 0  then
    table.insert(supported_thermostat_capabilities, capabilities.thermostatCoolingSetpoint.ID)
  end

  if running_state_supported then
    table.insert(supported_thermostat_capabilities, capabilities.thermostatOperatingState.ID)
  end

  return supported_thermostat_capabilities
end

function DeviceConfigurationHelpers.get_air_quality_optional_capabilities(device)
  local supported_air_quality_capabilities = {}

  local measurement_caps, level_caps = DeviceConfigurationHelpers.supported_level_measurements(device)

  for _, cap_id in ipairs(measurement_caps) do
    table.insert(supported_air_quality_capabilities, cap_id)
  end

  for _, cap_id in ipairs(level_caps) do
    table.insert(supported_air_quality_capabilities, cap_id)
  end

  return supported_air_quality_capabilities
end


local DeviceConfiguration = {}

function DeviceConfiguration.match_modular_profile_air_purifer(device)
  local optional_supported_component_capabilities = {}
  local main_component_capabilities = {}
  local hepa_filter_component_capabilities = {}
  local ac_filter_component_capabilties = {}
  local profile_name = "air-purifier-modular"

  local MAIN_COMPONENT_IDX = 1
  local CAPABILITIES_LIST_IDX = 2

  local humidity_eps = device:get_endpoints(clusters.RelativeHumidityMeasurement.ID)
  local temp_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureMeasurement.ID)
  if #humidity_eps > 0 then
    table.insert(main_component_capabilities, capabilities.relativeHumidityMeasurement.ID)
  end
  if #temp_eps > 0 then
    table.insert(main_component_capabilities, capabilities.temperatureMeasurement.ID)
  end

  local hepa_filter_eps = embedded_cluster_utils.get_endpoints(device, clusters.HepaFilterMonitoring.ID)
  local ac_filter_eps = embedded_cluster_utils.get_endpoints(device, clusters.ActivatedCarbonFilterMonitoring.ID)

  if #hepa_filter_eps > 0 then
    local filter_state_eps = embedded_cluster_utils.get_endpoints(device, clusters.HepaFilterMonitoring.ID, {feature_bitmap = clusters.HepaFilterMonitoring.types.Feature.CONDITION})
    if #filter_state_eps > 0 then
      table.insert(hepa_filter_component_capabilities, capabilities.filterState.ID)
    end

    table.insert(hepa_filter_component_capabilities, capabilities.filterStatus.ID)
  end
  if #ac_filter_eps > 0 then
    local filter_state_eps = embedded_cluster_utils.get_endpoints(device, clusters.ActivatedCarbonFilterMonitoring.ID, {feature_bitmap = clusters.ActivatedCarbonFilterMonitoring.types.Feature.CONDITION})
    if #filter_state_eps > 0 then
      table.insert(ac_filter_component_capabilties, capabilities.filterState.ID)
    end

    table.insert(ac_filter_component_capabilties, capabilities.filterStatus.ID)
  end

  -- determine fan capabilities, note that airPurifierFanMode is already mandatory
  local rock_eps = device:get_endpoints(clusters.FanControl.ID, {feature_bitmap = clusters.FanControl.types.Feature.ROCKING})
  local wind_eps = device:get_endpoints(clusters.FanControl.ID, {feature_bitmap = clusters.FanControl.types.FanControlFeature.WIND})

  if #rock_eps > 0 then
    table.insert(main_component_capabilities, capabilities.fanOscillationMode.ID)
  end
  if #wind_eps > 0 then
    table.insert(main_component_capabilities, capabilities.windMode.ID)
  end

  local thermostat_eps = device:get_endpoints(clusters.Thermostat.ID)

  if #thermostat_eps > 0 then
    -- thermostatMode and temperatureMeasurement should be expected if thermostat is present
    table.insert(main_component_capabilities, capabilities.thermostatMode.ID)

    -- only add temperatureMeasurement if it is not already added via TemperatureMeasurement cluster support
    if #temp_eps == 0 then
      table.insert(main_component_capabilities, capabilities.temperatureMeasurement.ID)
    end
    local thermostat_capabilities = DeviceConfigurationHelpers.get_thermostat_optional_capabilities(device)
    for _, capability_id in pairs(thermostat_capabilities) do
      table.insert(main_component_capabilities, capability_id)
    end
  end

  local aqs_eps = embedded_cluster_utils.get_endpoints(device, clusters.AirQuality.ID)
  if #aqs_eps > 0 then
    table.insert(main_component_capabilities, capabilities.airQualityHealthConcern.ID)
  end

  local supported_air_quality_capabilities = DeviceConfigurationHelpers.get_air_quality_optional_capabilities(device)
  for _, capability_id in pairs(supported_air_quality_capabilities) do
    table.insert(main_component_capabilities, capability_id)
  end

  table.insert(optional_supported_component_capabilities, {"main", main_component_capabilities})
  if #ac_filter_component_capabilties > 0 then
    table.insert(optional_supported_component_capabilities, {"activatedCarbonFilter", ac_filter_component_capabilties})
  end
  if #hepa_filter_component_capabilities > 0 then
    table.insert(optional_supported_component_capabilities, {"hepaFilter", hepa_filter_component_capabilities})
  end

  device:try_update_metadata({profile = profile_name, optional_component_capabilities = optional_supported_component_capabilities})

  -- earlier modular profile gating (min api v14, rpc 8) ensures we are running >= 0.57 FW.
  -- This gating specifies a workaround required only for 0.57 FW, which is not needed for 0.58 and higher.
  if version.api < 15 or version.rpc < 9 then
    -- add mandatory capabilities for subscription
    local total_supported_capabilities = optional_supported_component_capabilities
    table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX], capabilities.airPurifierFanMode.ID)
    table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX], capabilities.fanSpeedPercent.ID)
    table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX], capabilities.refresh.ID)
    table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX], capabilities.firmwareUpdate.ID)

    device:set_field(fields.SUPPORTED_COMPONENT_CAPABILITIES, total_supported_capabilities, { persist = true })
  end
end

function DeviceConfiguration.match_modular_profile_thermostat(device)
  local optional_supported_component_capabilities = {}
  local main_component_capabilities = {}
  local profile_name = "thermostat-modular"

  local humidity_eps = device:get_endpoints(clusters.RelativeHumidityMeasurement.ID)
  if #humidity_eps > 0 then
    table.insert(main_component_capabilities, capabilities.relativeHumidityMeasurement.ID)
  end

  -- determine fan capabilities
  local fan_eps = device:get_endpoints(clusters.FanControl.ID)
  local rock_eps = device:get_endpoints(clusters.FanControl.ID, {feature_bitmap = clusters.FanControl.types.Feature.ROCKING})
  local wind_eps = device:get_endpoints(clusters.FanControl.ID, {feature_bitmap = clusters.FanControl.types.FanControlFeature.WIND})

  if #fan_eps > 0 then
    table.insert(main_component_capabilities, capabilities.fanMode.ID)
  end
  if #rock_eps > 0 then
    table.insert(main_component_capabilities, capabilities.fanOscillationMode.ID)
  end
  if #wind_eps > 0 then
    table.insert(main_component_capabilities, capabilities.windMode.ID)
  end

  local thermostat_capabilities = DeviceConfigurationHelpers.get_thermostat_optional_capabilities(device)
  for _, capability_id in pairs(thermostat_capabilities) do
    table.insert(main_component_capabilities, capability_id)
  end

  local battery_supported = device:get_field(fields.profiling_data.BATTERY_SUPPORT)
  if battery_supported == fields.battery_support.BATTERY_LEVEL then
    table.insert(main_component_capabilities, capabilities.batteryLevel.ID)
  elseif battery_supported == fields.battery_support.BATTERY_PERCENTAGE then
    table.insert(main_component_capabilities, capabilities.battery.ID)
  end

  table.insert(optional_supported_component_capabilities, {"main", main_component_capabilities})
  device:try_update_metadata({profile = profile_name, optional_component_capabilities = optional_supported_component_capabilities})

  -- earlier modular profile gating (min api v14, rpc 8) ensures we are running >= 0.57 FW.
  -- This gating specifies a workaround required only for 0.57 FW, which is not needed for 0.58 and higher.
  if version.api < 15 or version.rpc < 9 then
    -- add mandatory capabilities for subscription
    local total_supported_capabilities = optional_supported_component_capabilities
    table.insert(main_component_capabilities, capabilities.thermostatMode.ID)
    table.insert(main_component_capabilities, capabilities.temperatureMeasurement.ID)
    table.insert(main_component_capabilities, capabilities.refresh.ID)
    table.insert(main_component_capabilities, capabilities.firmwareUpdate.ID)

    device:set_field(fields.SUPPORTED_COMPONENT_CAPABILITIES, total_supported_capabilities, { persist = true })
  end
end

function DeviceConfiguration.match_modular_profile_room_ac(device)
  local running_state_supported = device:get_field(fields.profiling_data.THERMOSTAT_RUNNING_STATE_SUPPORT)
  local humidity_eps = device:get_endpoints(clusters.RelativeHumidityMeasurement.ID)
  local optional_supported_component_capabilities = {}
  local main_component_capabilities = {}
  local profile_name = "room-air-conditioner-modular"

  if #humidity_eps > 0 then
    table.insert(main_component_capabilities, capabilities.relativeHumidityMeasurement.ID)
  end

  -- determine fan capabilities
  local fan_eps = device:get_endpoints(clusters.FanControl.ID)
  local wind_eps = device:get_endpoints(clusters.FanControl.ID, {feature_bitmap = clusters.FanControl.types.FanControlFeature.WIND})
  -- Note: Room AC does not support the rocking feature of FanControl.

  if #fan_eps > 0 then
    table.insert(main_component_capabilities, capabilities.airConditionerFanMode.ID)
    table.insert(main_component_capabilities, capabilities.fanSpeedPercent.ID)
  end
  if #wind_eps > 0 then
    table.insert(main_component_capabilities, capabilities.windMode.ID)
  end

  local heat_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.HEATING})
  local cool_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.COOLING})

  if #heat_eps > 0 then
    table.insert(main_component_capabilities, capabilities.thermostatHeatingSetpoint.ID)
  end
  if #cool_eps > 0  then
    table.insert(main_component_capabilities, capabilities.thermostatCoolingSetpoint.ID)
  end

  if running_state_supported then
    table.insert(main_component_capabilities, capabilities.thermostatOperatingState.ID)
  end

  table.insert(optional_supported_component_capabilities, {"main", main_component_capabilities})
  device:try_update_metadata({profile = profile_name, optional_component_capabilities = optional_supported_component_capabilities})

  -- earlier modular profile gating (min api v14, rpc 8) ensures we are running >= 0.57 FW.
  -- This gating specifies a workaround required only for 0.57 FW, which is not needed for 0.58 and higher.
  if version.api < 15 or version.rpc < 9 then
    -- add mandatory capabilities for subscription
    local total_supported_capabilities = optional_supported_component_capabilities
    table.insert(main_component_capabilities, capabilities.switch.ID)
    table.insert(main_component_capabilities, capabilities.temperatureMeasurement.ID)
    table.insert(main_component_capabilities, capabilities.thermostatMode.ID)
    table.insert(main_component_capabilities, capabilities.refresh.ID)
    table.insert(main_component_capabilities, capabilities.firmwareUpdate.ID)

    device:set_field(fields.SUPPORTED_COMPONENT_CAPABILITIES, total_supported_capabilities, { persist = true })
  end
end

local match_modular_device_type = {
  [fields.AP_DEVICE_TYPE_ID] = DeviceConfiguration.match_modular_profile_air_purifer,
  [fields.RAC_DEVICE_TYPE_ID] = DeviceConfiguration.match_modular_profile_room_ac,
  [fields.THERMOSTAT_DEVICE_TYPE_ID] = DeviceConfiguration.match_modular_profile_thermostat,
}

local function profiling_data_still_required(device)
  for _, field in pairs(fields.profiling_data) do
    if device:get_field(field) == nil then
      return true -- data still required if a field is nil
    end
  end
  return false
end

function DeviceConfiguration.match_profile(device)
  if profiling_data_still_required(device) then return end
  local primary_device_type = thermostat_utils.get_device_type(device)
  if version.api >= 14 and version.rpc >= 8 and match_modular_device_type[primary_device_type] then
    match_modular_device_type[primary_device_type](device)
    return
  else
    local legacy_device_cfg = require "thermostat_utils.legacy_device_configuration"
    legacy_device_cfg.match_profile(device)
  end
end

return DeviceConfiguration
