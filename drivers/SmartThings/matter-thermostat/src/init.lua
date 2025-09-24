-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local log = require "log"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "embedded-cluster-utils"
local im = require "st.matter.interaction_model"
local MatterDriver = require "st.matter.driver"
local utils = require "st.utils"
local version = require "version"

local SUPPORTED_COMPONENT_CAPABILITIES = "__supported_component_capabilities"
-- declare match_profile function for use throughout file
local match_profile

-- Include driver-side definitions when lua libs api version is < 10
if version.api < 10 then
  clusters.HepaFilterMonitoring = require "HepaFilterMonitoring"
  clusters.ActivatedCarbonFilterMonitoring = require "ActivatedCarbonFilterMonitoring"
  clusters.AirQuality = require "AirQuality"
  clusters.CarbonMonoxideConcentrationMeasurement = require "CarbonMonoxideConcentrationMeasurement"
  clusters.CarbonDioxideConcentrationMeasurement = require "CarbonDioxideConcentrationMeasurement"
  clusters.FormaldehydeConcentrationMeasurement = require "FormaldehydeConcentrationMeasurement"
  clusters.NitrogenDioxideConcentrationMeasurement = require "NitrogenDioxideConcentrationMeasurement"
  clusters.OzoneConcentrationMeasurement = require "OzoneConcentrationMeasurement"
  clusters.Pm1ConcentrationMeasurement = require "Pm1ConcentrationMeasurement"
  clusters.Pm10ConcentrationMeasurement = require "Pm10ConcentrationMeasurement"
  clusters.Pm25ConcentrationMeasurement = require "Pm25ConcentrationMeasurement"
  clusters.RadonConcentrationMeasurement = require "RadonConcentrationMeasurement"
  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement = require "TotalVolatileOrganicCompoundsConcentrationMeasurement"
  -- new modes add in Matter 1.2
  clusters.Thermostat.types.ThermostatSystemMode.DRY = 0x8
  clusters.Thermostat.types.ThermostatSystemMode.SLEEP = 0x9
end

local SAVED_SYSTEM_MODE_IB = "__saved_system_mode_ib"
local DISALLOWED_THERMOSTAT_MODES = "__DISALLOWED_CONTROL_OPERATIONS"
local OPTIONAL_THERMOSTAT_MODES_SEEN = "__OPTIONAL_THERMOSTAT_MODES_SEEN"

if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "ElectricalPowerMeasurement"
end

if version.api < 13 then
  clusters.WaterHeaterMode = require "WaterHeaterMode"
end

local THERMOSTAT_MODE_MAP = {
  [clusters.Thermostat.types.ThermostatSystemMode.OFF]               = capabilities.thermostatMode.thermostatMode.off,
  [clusters.Thermostat.types.ThermostatSystemMode.AUTO]              = capabilities.thermostatMode.thermostatMode.auto,
  [clusters.Thermostat.types.ThermostatSystemMode.COOL]              = capabilities.thermostatMode.thermostatMode.cool,
  [clusters.Thermostat.types.ThermostatSystemMode.HEAT]              = capabilities.thermostatMode.thermostatMode.heat,
  [clusters.Thermostat.types.ThermostatSystemMode.EMERGENCY_HEATING] = capabilities.thermostatMode.thermostatMode.emergency_heat,
  [clusters.Thermostat.types.ThermostatSystemMode.PRECOOLING]        = capabilities.thermostatMode.thermostatMode.precooling,
  [clusters.Thermostat.types.ThermostatSystemMode.FAN_ONLY]          = capabilities.thermostatMode.thermostatMode.fanonly,
  [clusters.Thermostat.types.ThermostatSystemMode.DRY]               = capabilities.thermostatMode.thermostatMode.dryair,
  [clusters.Thermostat.types.ThermostatSystemMode.SLEEP]             = capabilities.thermostatMode.thermostatMode.asleep,
}

local THERMOSTAT_OPERATING_MODE_MAP = {
  [0] = capabilities.thermostatOperatingState.thermostatOperatingState.heating,
  [1] = capabilities.thermostatOperatingState.thermostatOperatingState.cooling,
  [2] = capabilities.thermostatOperatingState.thermostatOperatingState.fan_only,
  [3] = capabilities.thermostatOperatingState.thermostatOperatingState.heating,
  [4] = capabilities.thermostatOperatingState.thermostatOperatingState.cooling,
  [5] = capabilities.thermostatOperatingState.thermostatOperatingState.fan_only,
  [6] = capabilities.thermostatOperatingState.thermostatOperatingState.fan_only,
}

local WIND_MODE_MAP = {
  [0] = capabilities.windMode.windMode.sleepWind,
  [1] = capabilities.windMode.windMode.naturalWind
}

local ROCK_MODE_MAP = {
  [0] = capabilities.fanOscillationMode.fanOscillationMode.horizontal,
  [1] = capabilities.fanOscillationMode.fanOscillationMode.vertical,
  [2] = capabilities.fanOscillationMode.fanOscillationMode.swing
}

local RAC_DEVICE_TYPE_ID = 0x0072
local AP_DEVICE_TYPE_ID = 0x002D
local FAN_DEVICE_TYPE_ID = 0x002B
local WATER_HEATER_DEVICE_TYPE_ID = 0x050F
local HEAT_PUMP_DEVICE_TYPE_ID = 0x0309
local THERMOSTAT_DEVICE_TYPE_ID = 0x0301
local ELECTRICAL_SENSOR_DEVICE_TYPE_ID = 0x0510

local MIN_ALLOWED_PERCENT_VALUE = 0
local MAX_ALLOWED_PERCENT_VALUE = 100

local CUMULATIVE_REPORTS_NOT_SUPPORTED = "__cumulative_reports_not_supported"
local LAST_IMPORTED_REPORT_TIMESTAMP = "__last_imported_report_timestamp"
local MINIMUM_ST_ENERGY_REPORT_INTERVAL = (15 * 60) -- 15 minutes, reported in seconds

local TOTAL_CUMULATIVE_ENERGY_IMPORTED_MAP = "__total_cumulative_energy_imported_map"
local SUPPORTED_WATER_HEATER_MODES_WITH_IDX = "__supported_water_heater_modes_with_idx"
local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
local MGM3_PPM_CONVERSION_FACTOR = 24.45

-- For RPC version >= 6, we can always assume that the values received from temperatureSetpoint
-- are in Celsius, but we still limit the setpoint range to somewhat reasonable values.
-- For RPC <= 5, this is a work around to handle when units for temperatureSetpoint is changed for the App.
-- When units are switched, we will never know the units of the received command value as the arguments don't contain the unit.
-- So to handle this we assume the following ranges considering usual thermostat/water-heater temperatures:
-- Thermostat:
--   1. if the received setpoint command value is in range 5 ~ 40, it is inferred as *C
--   2. if the received setpoint command value is in range 41 ~ 104, it is inferred as *F
local THERMOSTAT_MAX_TEMP_IN_C = version.rpc >= 6 and 100.0 or 40.0
local THERMOSTAT_MIN_TEMP_IN_C = version.rpc >= 6 and 0.0 or 5.0
-- Water Heater:
--   1. if the received setpoint command value is in range 30 ~ 80, it is inferred as *C
--   2. if the received setpoint command value is in range 86 ~ 176, it is inferred as *F
local WATER_HEATER_MAX_TEMP_IN_C = version.rpc >= 6 and 100.0 or 80.0
local WATER_HEATER_MIN_TEMP_IN_C = version.rpc >= 6 and 0.0 or 30.0

local setpoint_limit_device_field = {
  MIN_SETPOINT_DEADBAND_CHECKED = "MIN_SETPOINT_DEADBAND_CHECKED",
  MIN_HEAT = "MIN_HEAT",
  MAX_HEAT = "MAX_HEAT",
  MIN_COOL = "MIN_COOL",
  MAX_COOL = "MAX_COOL",
  MIN_DEADBAND = "MIN_DEADBAND",
  MIN_TEMP = "MIN_TEMP",
  MAX_TEMP = "MAX_TEMP"
}

local battery_support = {
  NO_BATTERY = "NO_BATTERY",
  BATTERY_LEVEL = "BATTERY_LEVEL",
  BATTERY_PERCENTAGE = "BATTERY_PERCENTAGE"
}

local profiling_data = {
  BATTERY_SUPPORT = "__BATTERY_SUPPORT",
  THERMOSTAT_RUNNING_STATE_SUPPORT = "__THERMOSTAT_RUNNING_STATE_SUPPORT"
}

local subscribed_attributes = {
  [capabilities.switch.ID] = {
    clusters.OnOff.attributes.OnOff
  },
  [capabilities.temperatureMeasurement.ID] = {
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
    clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
    clusters.TemperatureMeasurement.attributes.MaxMeasuredValue
  },
  [capabilities.relativeHumidityMeasurement.ID] = {
    clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
  },
  [capabilities.thermostatMode.ID] = {
    clusters.Thermostat.attributes.SystemMode,
    clusters.Thermostat.attributes.ControlSequenceOfOperation
  },
  [capabilities.thermostatOperatingState.ID] = {
    clusters.Thermostat.attributes.ThermostatRunningState
  },
  [capabilities.thermostatFanMode.ID] = {
    clusters.FanControl.attributes.FanModeSequence,
    clusters.FanControl.attributes.FanMode
  },
  [capabilities.thermostatCoolingSetpoint.ID] = {
    clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
    clusters.Thermostat.attributes.AbsMinCoolSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit
  },
  [capabilities.thermostatHeatingSetpoint.ID] = {
    clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
    clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit
  },
  [capabilities.airConditionerFanMode.ID] = {
    clusters.FanControl.attributes.FanModeSequence,
    clusters.FanControl.attributes.FanMode
  },
  [capabilities.airPurifierFanMode.ID] = {
    clusters.FanControl.attributes.FanModeSequence,
    clusters.FanControl.attributes.FanMode
  },
  [capabilities.fanMode.ID] = {
    clusters.FanControl.attributes.FanModeSequence,
    clusters.FanControl.attributes.FanMode
  },
  [capabilities.fanSpeedPercent.ID] = {
    clusters.FanControl.attributes.PercentCurrent
  },
  [capabilities.windMode.ID] = {
    clusters.FanControl.attributes.WindSupport,
    clusters.FanControl.attributes.WindSetting
  },
  [capabilities.fanOscillationMode.ID] = {
    clusters.FanControl.attributes.RockSupport,
    clusters.FanControl.attributes.RockSetting
  },
  [capabilities.battery.ID] = {
    clusters.PowerSource.attributes.BatPercentRemaining
  },
  [capabilities.batteryLevel.ID] = {
    clusters.PowerSource.attributes.BatChargeLevel
  },
  [capabilities.filterState.ID] = {
    clusters.HepaFilterMonitoring.attributes.Condition,
    clusters.ActivatedCarbonFilterMonitoring.attributes.Condition
  },
  [capabilities.filterStatus.ID] = {
    clusters.HepaFilterMonitoring.attributes.ChangeIndication,
    clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication
  },
  [capabilities.airQualityHealthConcern.ID] = {
    clusters.AirQuality.attributes.AirQuality
  },
  [capabilities.carbonMonoxideMeasurement.ID] = {
    clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue,
    clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.carbonMonoxideHealthConcern.ID] = {
    clusters.CarbonMonoxideConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.carbonDioxideMeasurement.ID] = {
    clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue,
    clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.carbonDioxideHealthConcern.ID] = {
    clusters.CarbonDioxideConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.nitrogenDioxideMeasurement.ID] = {
    clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasuredValue,
    clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasurementUnit
  },
  [capabilities.nitrogenDioxideHealthConcern.ID] = {
    clusters.NitrogenDioxideConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.ozoneMeasurement.ID] = {
    clusters.OzoneConcentrationMeasurement.attributes.MeasuredValue,
    clusters.OzoneConcentrationMeasurement.attributes.MeasurementUnit
  },
  [capabilities.ozoneHealthConcern.ID] = {
    clusters.OzoneConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.formaldehydeMeasurement.ID] = {
    clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue,
    clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.formaldehydeHealthConcern.ID] = {
    clusters.FormaldehydeConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.veryFineDustSensor.ID] = {
    clusters.Pm1ConcentrationMeasurement.attributes.MeasuredValue,
    clusters.Pm1ConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.veryFineDustHealthConcern.ID] = {
    clusters.Pm1ConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.fineDustHealthConcern.ID] = {
    clusters.Pm25ConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.fineDustSensor.ID] = {
    clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue,
    clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.dustSensor.ID] = {
    clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue,
    clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit,
    clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue,
    clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.dustHealthConcern.ID] = {
    clusters.Pm10ConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.radonMeasurement.ID] = {
    clusters.RadonConcentrationMeasurement.attributes.MeasuredValue,
    clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.radonHealthConcern.ID] = {
    clusters.RadonConcentrationMeasurement.attributes.LevelValue,
  },
  [capabilities.tvocMeasurement.ID] = {
    clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue,
    clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.tvocHealthConcern.ID] = {
    clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue
  },
  [capabilities.powerMeter.ID] = {
    clusters.ElectricalPowerMeasurement.attributes.ActivePower
  },
  [capabilities.mode.ID] = {
    clusters.WaterHeaterMode.attributes.CurrentMode,
    clusters.WaterHeaterMode.attributes.SupportedModes
  },
  [capabilities.powerConsumptionReport.ID] = {
    clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported,
    clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported
  },
  [capabilities.energyMeter.ID] = {
    clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported,
    clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported
  },
}

local function supports_capability_by_id_modular(device, capability, component)
  if not device:get_field(SUPPORTED_COMPONENT_CAPABILITIES) then
    device.log.warn_with({hub_logs = true}, "Device has overriden supports_capability_by_id, but does not have supported capabilities set.")
    return false
  end
  for _, component_capabilities in ipairs(device:get_field(SUPPORTED_COMPONENT_CAPABILITIES)) do
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

local function epoch_to_iso8601(time)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", time)
end

local get_total_cumulative_energy_imported = function(device)
  local total_cumulative_energy_imported = device:get_field(TOTAL_CUMULATIVE_ENERGY_IMPORTED_MAP) or {}
  local total_energy = 0
  for _, energyWh in pairs(total_cumulative_energy_imported) do
    total_energy = total_energy + energyWh
  end
  return total_energy
end

local function report_power_consumption_to_st_energy(device, latest_total_imported_energy_wh)
  local current_time = os.time()
  local last_time = device:get_field(LAST_IMPORTED_REPORT_TIMESTAMP) or 0

  -- Ensure that the previous report was sent at least 15 minutes ago
  if MINIMUM_ST_ENERGY_REPORT_INTERVAL >= (current_time - last_time) then
    return
  end

  device:set_field(LAST_IMPORTED_REPORT_TIMESTAMP, current_time, { persist = true })

  -- Calculate the energy delta between reports
  local energy_delta_wh = 0.0
  local previous_imported_report = device:get_latest_state("main", capabilities.powerConsumptionReport.ID,
    capabilities.powerConsumptionReport.powerConsumption.NAME)
  if previous_imported_report and previous_imported_report.energy then
    energy_delta_wh = math.max(latest_total_imported_energy_wh - previous_imported_report.energy, 0.0)
  end

  -- Report the energy consumed during the time interval. The unit of these values should be 'Wh'
  device:emit_component_event(device.profile.components["main"], capabilities.powerConsumptionReport.powerConsumption({
    start = epoch_to_iso8601(last_time),
    ["end"] = epoch_to_iso8601(current_time - 1),
    deltaEnergy = energy_delta_wh,
    energy = latest_total_imported_energy_wh
  }))
end

local function device_removed(driver, device)
  device.log.info("device removed")
end

local function tbl_contains(array, value)
  for idx, element in ipairs(array) do
    if element == value then
      return true, idx
    end
  end
  return false, nil
end

local function get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

local function set_field_for_endpoint(device, field, endpoint, value, additional_params)
  device:set_field(string.format("%s_%d", field, endpoint), value, additional_params)
end

local function find_default_endpoint(device, cluster)
  local res = device.MATTER_DEFAULT_ENDPOINT
  local eps = embedded_cluster_utils.get_endpoints(device, cluster)
  table.sort(eps)
  for _, v in ipairs(eps) do
    if v ~= 0 then --0 is the matter RootNode endpoint
      return v
    end
  end
  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return res
end

local function component_to_endpoint(device, component_name, cluster_id)
  -- Use the find_default_endpoint function to return the first endpoint that
  -- supports a given cluster.
  local component_to_endpoint_map = device:get_field(COMPONENT_TO_ENDPOINT_MAP)
  if component_to_endpoint_map ~= nil and component_to_endpoint_map[component_name] ~= nil then
    return component_to_endpoint_map[component_name]
  end
  if not cluster_id then return device.MATTER_DEFAULT_ENDPOINT end
  return find_default_endpoint(device, cluster_id)
end

local endpoint_to_component = function (device, endpoint_id)
  local component_to_endpoint_map = device:get_field(COMPONENT_TO_ENDPOINT_MAP)
  if component_to_endpoint_map ~= nil then
    for comp, ep in pairs(component_to_endpoint_map) do
      if ep == endpoint_id then
        return comp
      end
    end
  end
  return "main"
end

local function device_init(driver, device)
  if device:get_field(SUPPORTED_COMPONENT_CAPABILITIES) and (version.api < 15 or version.rpc < 9) then
    -- assume that device is using a modular profile on 0.57 FW, override supports_capability_by_id
    -- library function to utilize optional capabilities
    device:extend_device("supports_capability_by_id", supports_capability_by_id_modular)
  end
  device:subscribe()
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  if not device:get_field(setpoint_limit_device_field.MIN_SETPOINT_DEADBAND_CHECKED) then
    local auto_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.AUTOMODE})
    --Query min setpoint deadband if needed
    if #auto_eps ~= 0 and device:get_field(setpoint_limit_device_field.MIN_DEADBAND) == nil then
      local deadband_read = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
      deadband_read:merge(clusters.Thermostat.attributes.MinSetpointDeadBand:read())
      device:send(deadband_read)
    end
  end

  -- device energy reporting must be handled cumulatively, periodically, or by both simulatanously.
  -- To ensure a single source of truth, we only handle a device's periodic reporting if cumulative reporting is not supported.
  local electrical_energy_measurement_eps = embedded_cluster_utils.get_endpoints(device, clusters.ElectricalEnergyMeasurement.ID)
  if #electrical_energy_measurement_eps > 0 then
    local cumulative_energy_eps = embedded_cluster_utils.get_endpoints(
      device,
      clusters.ElectricalEnergyMeasurement.ID,
      {feature_bitmap = clusters.ElectricalEnergyMeasurement.types.Feature.CUMULATIVE_ENERGY}
    )
    if #cumulative_energy_eps == 0 then device:set_field(CUMULATIVE_REPORTS_NOT_SUPPORTED, true, {persist = false}) end
  end
end

local function info_changed(driver, device, event, args)
  if device:get_field(SUPPORTED_COMPONENT_CAPABILITIES) then
    -- This indicates the device should be using a modular profile, so
    -- re-up subscription with new capabilities using the modular supports_capability override
    device:extend_device("supports_capability_by_id", supports_capability_by_id_modular)
  end

  if device.profile.id ~= args.old_st_store.profile.id then
    device:subscribe()
  end
end

local function get_endpoints_for_dt(device, device_type)
  local endpoints = {}
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == device_type then
        table.insert(endpoints, ep.endpoint_id)
        break
      end
    end
  end
  table.sort(endpoints)
  return endpoints
end

local function get_device_type(device)
  -- For cases where a device has multiple device types, this list indicates which
  -- device type will be the "main" device type for purposes of selecting a profile
  -- with an appropriate category. This is done to promote consistency between
  -- devices with similar device type compositions that may report their device types
  -- listed in different orders
  local device_type_priority = {
    [HEAT_PUMP_DEVICE_TYPE_ID] = 1,
    [RAC_DEVICE_TYPE_ID] = 2,
    [AP_DEVICE_TYPE_ID] = 3,
    [THERMOSTAT_DEVICE_TYPE_ID] = 4,
    [FAN_DEVICE_TYPE_ID] = 5,
    [WATER_HEATER_DEVICE_TYPE_ID] = 6,
  }

  local main_device_type = false

  for _, ep in ipairs(device.endpoints) do
    if ep.device_types ~= nil then
      for _, dt in ipairs(ep.device_types) do
        if not device_type_priority[main_device_type] or (device_type_priority[dt.device_type_id] and
          device_type_priority[dt.device_type_id] < device_type_priority[main_device_type]) then
          main_device_type = dt.device_type_id
        end
      end
    end
  end

  return main_device_type
end

local AIR_QUALITY_MAP = {
  {capabilities.carbonDioxideMeasurement.ID,     "-co2",   clusters.CarbonDioxideConcentrationMeasurement},
  {capabilities.carbonDioxideHealthConcern.ID,   "-co2",   clusters.CarbonDioxideConcentrationMeasurement},
  {capabilities.carbonMonoxideMeasurement.ID,    "-co",    clusters.CarbonMonoxideConcentrationMeasurement},
  {capabilities.carbonMonoxideHealthConcern.ID,  "-co",    clusters.CarbonMonoxideConcentrationMeasurement},
  {capabilities.dustSensor.ID,                   "-pm10",  clusters.Pm10ConcentrationMeasurement},
  {capabilities.dustHealthConcern.ID,            "-pm10",  clusters.Pm10ConcentrationMeasurement},
  {capabilities.fineDustSensor.ID,               "-pm25",  clusters.Pm25ConcentrationMeasurement},
  {capabilities.fineDustHealthConcern.ID,        "-pm25",  clusters.Pm25ConcentrationMeasurement},
  {capabilities.formaldehydeMeasurement.ID,      "-ch2o",  clusters.FormaldehydeConcentrationMeasurement},
  {capabilities.formaldehydeHealthConcern.ID,    "-ch2o",  clusters.FormaldehydeConcentrationMeasurement},
  {capabilities.nitrogenDioxideHealthConcern.ID, "-no2",   clusters.NitrogenDioxideConcentrationMeasurement},
  {capabilities.nitrogenDioxideMeasurement.ID,   "-no2",   clusters.NitrogenDioxideConcentrationMeasurement},
  {capabilities.ozoneHealthConcern.ID,           "-ozone", clusters.OzoneConcentrationMeasurement},
  {capabilities.ozoneMeasurement.ID,             "-ozone", clusters.OzoneConcentrationMeasurement},
  {capabilities.radonHealthConcern.ID,           "-radon", clusters.RadonConcentrationMeasurement},
  {capabilities.radonMeasurement.ID,             "-radon", clusters.RadonConcentrationMeasurement},
  {capabilities.tvocHealthConcern.ID,            "-tvoc",  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement},
  {capabilities.tvocMeasurement.ID,              "-tvoc",  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement},
  {capabilities.veryFineDustHealthConcern.ID,    "-pm1",   clusters.Pm1ConcentrationMeasurement},
  {capabilities.veryFineDustSensor.ID,           "-pm1",   clusters.Pm1ConcentrationMeasurement},
}

local function create_level_measurement_profile(device)
  local meas_name, level_name = "", ""
  for _, details in ipairs(AIR_QUALITY_MAP) do
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

local function supported_level_measurements(device)
  local measurement_caps, level_caps = {}, {}
  for _, details in ipairs(AIR_QUALITY_MAP) do
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

local function create_air_quality_sensor_profile(device)
  local aqs_eps = embedded_cluster_utils.get_endpoints(device, clusters.AirQuality.ID)
  local profile_name = ""
  if #aqs_eps > 0 then
    profile_name = profile_name .. "-aqs"
  end
  local meas_name, level_name = create_level_measurement_profile(device)
  if meas_name ~= "" then
    profile_name = profile_name .. meas_name .. "-meas"
  end
  if level_name ~= "" then
    profile_name = profile_name .. level_name .. "-level"
  end
  return profile_name
end

local function create_fan_profile(device)
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

local function create_air_purifier_profile(device)
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
  local fan_profile = create_fan_profile(device)
  if fan_profile ~= "" then
    fan_eps_seen = true
  end
  fan_profile = string.gsub(fan_profile, "-fan", "")
  profile_name = profile_name .. fan_profile

  return profile_name, fan_eps_seen
end

local function create_thermostat_modes_profile(device)
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

local function profiling_data_still_required(device)
  for _, field in pairs(profiling_data) do
    if device:get_field(field) == nil then
      return true -- data still required if a field is nil
    end
  end
  return false
end

local function match_profile_switch(driver, device)
  if profiling_data_still_required(device) then return end

  local running_state_supported = device:get_field(profiling_data.THERMOSTAT_RUNNING_STATE_SUPPORT)
  local battery_supported = device:get_field(profiling_data.BATTERY_SUPPORT)

  local thermostat_eps = device:get_endpoints(clusters.Thermostat.ID)
  local humidity_eps = device:get_endpoints(clusters.RelativeHumidityMeasurement.ID)
  local device_type = get_device_type(device)
  local profile_name
  if device_type == RAC_DEVICE_TYPE_ID then
    profile_name = "room-air-conditioner"

    if #humidity_eps > 0 then
      profile_name = profile_name .. "-humidity"
    end

    -- Room AC does not support the rocking feature of FanControl.
    local fan_name = create_fan_profile(device)
    fan_name = string.gsub(fan_name, "-rock", "")
    profile_name = profile_name .. fan_name

    local thermostat_modes = create_thermostat_modes_profile(device)
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

  elseif device_type == FAN_DEVICE_TYPE_ID then
    profile_name = create_fan_profile(device)
    -- remove leading "-"
    profile_name = string.sub(profile_name, 2)
    if profile_name == "fan" then
      profile_name = "fan-generic"
    end

  elseif device_type == AP_DEVICE_TYPE_ID then
    local fan_eps_found
    profile_name, fan_eps_found = create_air_purifier_profile(device)
    if #thermostat_eps > 0 then
      profile_name = profile_name .. "-thermostat"

      if #humidity_eps > 0 then
        profile_name = profile_name .. "-humidity"
      end

      if fan_eps_found then
        profile_name = profile_name .. "-fan"
      end

      local thermostat_modes = create_thermostat_modes_profile(device)
      if thermostat_modes ~= "No Heating nor Cooling Support" then
        profile_name = profile_name .. thermostat_modes
      end

      if not running_state_supported then
        profile_name = profile_name .. "-nostate"
      end

      if battery_supported == battery_support.BATTERY_LEVEL then
        profile_name = profile_name .. "-batteryLevel"
      elseif battery_supported == battery_support.NO_BATTERY then
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
    profile_name = profile_name .. create_air_quality_sensor_profile(device)
  elseif device_type == WATER_HEATER_DEVICE_TYPE_ID then
    -- If a Water Heater is composed of Electrical Sensor device type, it must support both ElectricalEnergyMeasurement and
    -- ElectricalPowerMeasurement clusters.
    local electrical_sensor_eps = get_endpoints_for_dt(device, ELECTRICAL_SENSOR_DEVICE_TYPE_ID) or {}
    if #electrical_sensor_eps > 0 then
      profile_name = "water-heater-power-energy-powerConsumption"
    end
  elseif device_type == HEAT_PUMP_DEVICE_TYPE_ID then
    profile_name = "heat-pump"
    local MAX_HEAT_PUMP_THERMOSTAT_COMPONENTS = 2
    for i = 1, math.min(MAX_HEAT_PUMP_THERMOSTAT_COMPONENTS, #thermostat_eps) do
        profile_name = profile_name .. "-thermostat"
        if tbl_contains(humidity_eps, thermostat_eps[i]) then
          profile_name = profile_name .. "-humidity"
        end
    end
  elseif #thermostat_eps > 0 then
    profile_name = "thermostat"

    if #humidity_eps > 0 then
      profile_name = profile_name .. "-humidity"
    end

    -- thermostat profiles support neither wind nor rocking FanControl attributes
    local fan_name = create_fan_profile(device)
    if fan_name ~= "" then
      profile_name = profile_name .. "-fan"
    end

    local thermostat_modes = create_thermostat_modes_profile(device)
    if thermostat_modes == "No Heating nor Cooling Support" then
      device.log.warn_with({hub_logs=true}, "Device does not support either heating or cooling. No matching profile")
      return
    else
      profile_name = profile_name .. thermostat_modes
    end

    if not running_state_supported then
      profile_name = profile_name .. "-nostate"
    end

    if battery_supported == battery_support.BATTERY_LEVEL then
      profile_name = profile_name .. "-batteryLevel"
    elseif battery_supported == battery_support.NO_BATTERY then
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
  for _, field in pairs(profiling_data) do
    device:set_field(field, nil)
  end
end

local function get_thermostat_optional_capabilities(device)
  local heat_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.HEATING})
  local cool_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.COOLING})
  local running_state_supported = device:get_field(profiling_data.THERMOSTAT_RUNNING_STATE_SUPPORT)

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

local function get_air_quality_optional_capabilities(device)
  local supported_air_quality_capabilities = {}

  local measurement_caps, level_caps = supported_level_measurements(device)

  for _, cap_id in ipairs(measurement_caps) do
    table.insert(supported_air_quality_capabilities, cap_id)
  end

  for _, cap_id in ipairs(level_caps) do
    table.insert(supported_air_quality_capabilities, cap_id)
  end

  return supported_air_quality_capabilities
end

local function match_modular_profile_air_purifer(driver, device)
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
    local thermostat_capabilities = get_thermostat_optional_capabilities(device)
    for _, capability_id in pairs(thermostat_capabilities) do
      table.insert(main_component_capabilities, capability_id)
    end
  end

  local aqs_eps = embedded_cluster_utils.get_endpoints(device, clusters.AirQuality.ID)
  if #aqs_eps > 0 then
    table.insert(main_component_capabilities, capabilities.airQualityHealthConcern.ID)
  end

  local supported_air_quality_capabilities = get_air_quality_optional_capabilities(device)
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

    device:set_field(SUPPORTED_COMPONENT_CAPABILITIES, total_supported_capabilities, { persist = true })
  end
end

local function match_modular_profile_thermostat(driver, device)
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
    table.insert(main_component_capabilities, capabilities.fanSpeedPercent.ID)
  end
  if #rock_eps > 0 then
    table.insert(main_component_capabilities, capabilities.fanOscillationMode.ID)
  end
  if #wind_eps > 0 then
    table.insert(main_component_capabilities, capabilities.windMode.ID)
  end

  local thermostat_capabilities = get_thermostat_optional_capabilities(device)
  for _, capability_id in pairs(thermostat_capabilities) do
    table.insert(main_component_capabilities, capability_id)
  end

  local battery_supported = device:get_field(profiling_data.BATTERY_SUPPORT)
  if battery_supported == battery_support.BATTERY_LEVEL then
    table.insert(main_component_capabilities, capabilities.batteryLevel.ID)
  elseif battery_supported == battery_support.BATTERY_PERCENTAGE then
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

    device:set_field(SUPPORTED_COMPONENT_CAPABILITIES, total_supported_capabilities, { persist = true })
  end
end

local function match_modular_profile_room_ac(driver, device)
  local running_state_supported = device:get_field(profiling_data.THERMOSTAT_RUNNING_STATE_SUPPORT)
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

    device:set_field(SUPPORTED_COMPONENT_CAPABILITIES, total_supported_capabilities, { persist = true })
  end
end

local function match_modular_profile(driver, device, device_type)
  if profiling_data_still_required(device) then return end

  if device_type == AP_DEVICE_TYPE_ID then
    match_modular_profile_air_purifer(driver, device)
  elseif device_type == RAC_DEVICE_TYPE_ID then
    match_modular_profile_room_ac(driver, device)
  elseif device_type == THERMOSTAT_DEVICE_TYPE_ID then
    match_modular_profile_thermostat(driver, device)
  else
    device.log.warn_with({hub_logs=true}, "Device type is not supported by modular profile in thermostat driver, trying profile switch instead")
    match_profile_switch(driver, device)
    return
  end

  -- clear all profiling data fields after profiling is complete.
  for _, field in pairs(profiling_data) do
    device:set_field(field, nil)
  end
end

local function supports_modular_profile(device)
  local supported_modular_device_types = {
    AP_DEVICE_TYPE_ID,
    RAC_DEVICE_TYPE_ID,
    THERMOSTAT_DEVICE_TYPE_ID,
  }
  local device_type = get_device_type(device)
  if not tbl_contains(supported_modular_device_types, device_type) then
    device_type = false
  end
  return version.api >= 14 and version.rpc >= 8 and device_type
end

function match_profile(driver, device)
  local modular_device_type = supports_modular_profile(device)
  if modular_device_type then
    match_modular_profile(driver, device, modular_device_type)
  else
    match_profile_switch(driver, device)
  end
end

local function do_configure(driver, device)
  match_profile(driver, device)
end

local function driver_switched(driver, device)
  match_profile(driver, device)
end

local function device_added(driver, device)
  local req = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  req:merge(clusters.Thermostat.attributes.ControlSequenceOfOperation:read(device))
  req:merge(clusters.FanControl.attributes.FanModeSequence:read(device))
  req:merge(clusters.FanControl.attributes.WindSupport:read(device))
  req:merge(clusters.FanControl.attributes.RockSupport:read(device))

  local thermostat_eps = device:get_endpoints(clusters.Thermostat.ID)
  if #thermostat_eps > 0 then
    req:merge(clusters.Thermostat.attributes.AttributeList:read(device))
  else
    device:set_field(profiling_data.THERMOSTAT_RUNNING_STATE_SUPPORT, false)
  end
  local battery_feature_eps = device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
  if #battery_feature_eps > 0 then
    req:merge(clusters.PowerSource.attributes.AttributeList:read(device))
  else
    device:set_field(profiling_data.BATTERY_SUPPORT, battery_support.NO_BATTERY)
  end
  device:send(req)
  local heat_pump_eps = get_endpoints_for_dt(device, HEAT_PUMP_DEVICE_TYPE_ID) or {}
  if #heat_pump_eps > 0 then
    local thermostat_eps = get_endpoints_for_dt(device, THERMOSTAT_DEVICE_TYPE_ID) or {}
    local component_to_endpoint_map = {
      ["thermostatOne"] = thermostat_eps[1],
      ["thermostatTwo"] = thermostat_eps[2],
    }
    device:set_field(COMPONENT_TO_ENDPOINT_MAP, component_to_endpoint_map, {persist = true})
  end
end

local function store_unit_factory(capability_name)
  return function(driver, device, ib, response)
    device:set_field(capability_name.."_unit", ib.data.value, {persist = true})
  end
end

local units = {
  PPM = 0,
  PPB = 1,
  PPT = 2,
  MGM3 = 3,
  UGM3 = 4,
  NGM3 = 5,
  PM3 = 6,
  BQM3 = 7,
  PCIL = 0xFF -- not in matter spec
}

local unit_strings = {
  [units.PPM] = "ppm",
  [units.PPB] = "ppb",
  [units.PPT] = "ppt",
  [units.MGM3] = "mg/m^3",
  [units.NGM3] = "ng/m^3",
  [units.UGM3] = "μg/m^3",
  [units.BQM3] = "Bq/m^3",
  [units.PCIL] = "pCi/L"
}

local unit_default = {
  [capabilities.carbonMonoxideMeasurement.NAME] = units.PPM,
  [capabilities.carbonDioxideMeasurement.NAME] = units.PPM,
  [capabilities.nitrogenDioxideMeasurement.NAME] = units.PPM,
  [capabilities.ozoneMeasurement.NAME] = units.PPM,
  [capabilities.formaldehydeMeasurement.NAME] = units.PPM,
  [capabilities.veryFineDustSensor.NAME] = units.UGM3,
  [capabilities.fineDustSensor.NAME] = units.UGM3,
  [capabilities.dustSensor.NAME] = units.UGM3,
  [capabilities.radonMeasurement.NAME] = units.BQM3,
  [capabilities.tvocMeasurement.NAME] = units.PPB  -- TVOC is typically within the range of 0-5500 ppb, with good to moderate values being < 660 ppb
}

-- All ConcentrationMesurement clusters inherit from the same base cluster definitions,
-- so CarbonMonoxideConcentratinMeasurement is used below but the same enum types exist
-- in all ConcentrationMeasurement clusters
local level_strings = {
  [clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.UNKNOWN] = "unknown",
  [clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.LOW] = "good",
  [clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.MEDIUM] = "moderate",
  [clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.HIGH] = "unhealthy",
  [clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.CRITICAL] = "hazardous",
}

-- measured in g/mol
local molecular_weights = {
  [capabilities.carbonDioxideMeasurement.NAME] = 44.010,
  [capabilities.nitrogenDioxideMeasurement.NAME] = 28.014,
  [capabilities.ozoneMeasurement.NAME] = 48.0,
  [capabilities.formaldehydeMeasurement.NAME] = 30.031,
  [capabilities.veryFineDustSensor.NAME] = "N/A",
  [capabilities.fineDustSensor.NAME] = "N/A",
  [capabilities.dustSensor.NAME] = "N/A",
  [capabilities.radonMeasurement.NAME] = 222.018,
  [capabilities.tvocMeasurement.NAME] = "N/A",
}

local conversion_tables = {
  [units.PPM] = {
    [units.PPM] = function(value) return utils.round(value) end,
    [units.PPB] = function(value) return utils.round(value * (10^3)) end,
    [units.UGM3] = function(value, molecular_weight) return utils.round((value * molecular_weight * 10^3) / MGM3_PPM_CONVERSION_FACTOR) end,
    [units.MGM3] = function(value, molecular_weight) return utils.round((value * molecular_weight) / MGM3_PPM_CONVERSION_FACTOR) end,
  },
  [units.PPB] = {
    [units.PPM] = function(value) return utils.round(value/(10^3)) end,
    [units.PPB] = function(value) return utils.round(value) end,
  },
  [units.PPT] = {
    [units.PPM] = function(value) return utils.round(value/(10^6)) end
  },
  [units.MGM3] = {
    [units.UGM3] = function(value) return utils.round(value * (10^3)) end,
    [units.PPM] = function(value, molecular_weight) return utils.round((value * MGM3_PPM_CONVERSION_FACTOR) / molecular_weight) end,
  },
  [units.UGM3] = {
    [units.UGM3] = function(value) return utils.round(value) end,
    [units.PPM] = function(value, molecular_weight) return utils.round((value * MGM3_PPM_CONVERSION_FACTOR) / (molecular_weight * 10^3)) end,
  },
  [units.NGM3] = {
    [units.UGM3] = function(value) return utils.round(value/(10^3)) end
  },
  [units.BQM3] = {
    [units.PCIL] = function(value) return utils.round(value/37) end
  },
}

local function unit_conversion(value, from_unit, to_unit, capability_name)
  local conversion_function = conversion_tables[from_unit][to_unit]
  if not conversion_function then
    log.info_with( {hub_logs = true} , string.format("Unsupported unit conversion from %s to %s", unit_strings[from_unit], unit_strings[to_unit]))
    return
  end

  if not value then
    log.info_with( {hub_logs = true} , "unit conversion value is nil")
    return
  end

  return conversion_function(value, molecular_weights[capability_name])
end

local function measurementHandlerFactory(capability_name, attribute, target_unit)
  return function(driver, device, ib, response)
    local reporting_unit = device:get_field(capability_name.."_unit")

    if not reporting_unit then
      reporting_unit = unit_default[capability_name]
      device:set_field(capability_name.."_unit", reporting_unit, {persist = true})
    end

    local value = nil
    if reporting_unit then
      value = unit_conversion(ib.data.value, reporting_unit, target_unit, capability_name)
    end

    if value then
      device:emit_event_for_endpoint(ib.endpoint_id, attribute({value = value, unit = unit_strings[target_unit]}))
      -- handle case where device profile supports both fineDustLevel and dustLevel
      if capability_name == capabilities.fineDustSensor.NAME and device:supports_capability(capabilities.dustSensor) then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.dustSensor.fineDustLevel({value = value, unit = unit_strings[target_unit]}))
      end
    end
  end
end

local function levelHandlerFactory(attribute)
  return function(driver, device, ib, response)
    device:emit_event_for_endpoint(ib.endpoint_id, attribute(level_strings[ib.data.value]))
  end
end

-- handlers
local function air_quality_attr_handler(driver, device, ib, response)
  local state = ib.data.value
  if state == 0 then -- Unknown
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.unknown())
  elseif state == 1 then -- Good
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.good())
  elseif state == 2 then -- Fair
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.moderate())
  elseif state == 3 then -- Moderate
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.slightlyUnhealthy())
  elseif state == 4 then -- Poor
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.unhealthy())
  elseif state == 5 then -- VeryPoor
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.veryUnhealthy())
  elseif state == 6 then -- ExtremelyPoor
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.hazardous())
  end
end

local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  end
end

local function temp_event_handler(attribute)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local unit = "C"

    -- Only emit the capability for RPC version >= 5, since unit conversion for
    -- range capabilities is only supported in that case.
    if version.rpc >= 5 then
      local event
      if attribute == capabilities.thermostatCoolingSetpoint.coolingSetpoint then
        local range = {
          minimum = device:get_field(setpoint_limit_device_field.MIN_COOL) or THERMOSTAT_MIN_TEMP_IN_C,
          maximum = device:get_field(setpoint_limit_device_field.MAX_COOL) or THERMOSTAT_MAX_TEMP_IN_C,
          step = 0.1
        }
        event = capabilities.thermostatCoolingSetpoint.coolingSetpointRange({value = range, unit = unit})
        device:emit_event_for_endpoint(ib.endpoint_id, event)
      elseif attribute == capabilities.thermostatHeatingSetpoint.heatingSetpoint then
        local MAX_TEMP_IN_C = THERMOSTAT_MAX_TEMP_IN_C
        local MIN_TEMP_IN_C = THERMOSTAT_MIN_TEMP_IN_C
        local is_water_heater_device = get_device_type(device) == WATER_HEATER_DEVICE_TYPE_ID
        if is_water_heater_device then
          MAX_TEMP_IN_C = WATER_HEATER_MAX_TEMP_IN_C
          MIN_TEMP_IN_C = WATER_HEATER_MIN_TEMP_IN_C
        end

        local range = {
          minimum = device:get_field(setpoint_limit_device_field.MIN_HEAT) or MIN_TEMP_IN_C,
          maximum = device:get_field(setpoint_limit_device_field.MAX_HEAT) or MAX_TEMP_IN_C,
          step = 0.1
        }
        event = capabilities.thermostatHeatingSetpoint.heatingSetpointRange({value = range, unit = unit})
        device:emit_event_for_endpoint(ib.endpoint_id, event)
      end
    end

    local temp = ib.data.value / 100.0
    device:emit_event_for_endpoint(ib.endpoint_id, attribute({value = temp, unit = unit}))
  end
end

local temp_attr_handler_factory = function(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local temp = ib.data.value / 100.0
    local unit = "C"
    temp = utils.clamp_value(temp, THERMOSTAT_MIN_TEMP_IN_C, THERMOSTAT_MAX_TEMP_IN_C)
    set_field_for_endpoint(device, minOrMax, ib.endpoint_id, temp)
    local min = get_field_for_endpoint(device, setpoint_limit_device_field.MIN_TEMP, ib.endpoint_id)
    local max = get_field_for_endpoint(device, setpoint_limit_device_field.MAX_TEMP, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        -- Only emit the capability for RPC version >= 5 (unit conversion for
        -- temperature range capability is only supported for RPC >= 5)
        if version.rpc >= 5 then
          device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = min, maximum = max }, unit = unit }))
        end
        set_field_for_endpoint(device, setpoint_limit_device_field.MIN_TEMP, ib.endpoint_id, nil)
        set_field_for_endpoint(device, setpoint_limit_device_field.MAX_TEMP, ib.endpoint_id, nil)
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min temperature %d that is not lower than the reported max temperature %d", min, max))
      end
    end
  end
end

local function humidity_attr_handler(driver, device, ib, response)
  local humidity = math.floor(ib.data.value / 100.0)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(humidity))
end

local function system_mode_handler(driver, device, ib, response)
  if device:get_field(OPTIONAL_THERMOSTAT_MODES_SEEN) == nil then -- this being nil means the sequence_of_operation_handler hasn't run.
    device.log.info_with({hub_logs = true}, "In the SystemMode handler: ControlSequenceOfOperation has not run yet. Exiting early.")
    device:set_field(SAVED_SYSTEM_MODE_IB, ib)
    return
  end

  local supported_modes = device:get_latest_state(
    device:endpoint_to_component(ib.endpoint_id),
    capabilities.thermostatMode.ID,
    capabilities.thermostatMode.supportedThermostatModes.NAME
  ) or {}
  -- check that the given mode was in the supported modes list
  if tbl_contains(supported_modes, THERMOSTAT_MODE_MAP[ib.data.value].NAME) then
    device:emit_event_for_endpoint(ib.endpoint_id, THERMOSTAT_MODE_MAP[ib.data.value]())
    return
  end
  -- if the value is not found in the supported modes list, check if it's disallowed and early return if so.
  local disallowed_thermostat_modes = device:get_field(DISALLOWED_THERMOSTAT_MODES) or {}
  if tbl_contains(disallowed_thermostat_modes, THERMOSTAT_MODE_MAP[ib.data.value].NAME) then
    return
  end
  -- if we get here, then the reported mode is allowed and not in our mode map
  -- add the mode to the OPTIONAL_THERMOSTAT_MODES_SEEN and supportedThermostatModes tables
  local optional_modes_seen = utils.deep_copy(device:get_field(OPTIONAL_THERMOSTAT_MODES_SEEN)) or {}
  table.insert(optional_modes_seen, THERMOSTAT_MODE_MAP[ib.data.value].NAME)
  device:set_field(OPTIONAL_THERMOSTAT_MODES_SEEN, optional_modes_seen, {persist=true})
  local sm_copy = utils.deep_copy(supported_modes)
  table.insert(sm_copy, THERMOSTAT_MODE_MAP[ib.data.value].NAME)
  local supported_modes_event = capabilities.thermostatMode.supportedThermostatModes(sm_copy, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, supported_modes_event)
  device:emit_event_for_endpoint(ib.endpoint_id, THERMOSTAT_MODE_MAP[ib.data.value]())
end

local function running_state_handler(driver, device, ib, response)
  for mode, operating_state in pairs(THERMOSTAT_OPERATING_MODE_MAP) do
    if ((ib.data.value >> mode) & 1) > 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, operating_state())
      return
    end
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatOperatingState.thermostatOperatingState.idle())
end

local function sequence_of_operation_handler(driver, device, ib, response)
  -- The ControlSequenceOfOperation attribute only directly specifies what can't be operated by the operating environment, not what can.
  -- However, we assert here that a Cooling enum value implies that SystemMode supports cooling, and the same for a Heating enum.
  -- We also assert that Off is supported, though per spec this is optional.
  if device:get_field(OPTIONAL_THERMOSTAT_MODES_SEEN) == nil then
    device:set_field(OPTIONAL_THERMOSTAT_MODES_SEEN, {capabilities.thermostatMode.thermostatMode.off.NAME}, {persist=true})
  end
  local supported_modes = utils.deep_copy(device:get_field(OPTIONAL_THERMOSTAT_MODES_SEEN))
  local disallowed_mode_operations = {}

  local modes_for_inclusion = {}
  if ib.data.value <= clusters.Thermostat.attributes.ControlSequenceOfOperation.COOLING_WITH_REHEAT then
    local _, found_idx = tbl_contains(supported_modes, capabilities.thermostatMode.thermostatMode.emergency_heat.NAME)
    if found_idx then
      table.remove(supported_modes, found_idx) -- if seen before, remove now
    end
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.cool.NAME)
    table.insert(disallowed_mode_operations, capabilities.thermostatMode.thermostatMode.heat.NAME)
    table.insert(disallowed_mode_operations, capabilities.thermostatMode.thermostatMode.emergency_heat.NAME)
  elseif ib.data.value <= clusters.Thermostat.attributes.ControlSequenceOfOperation.HEATING_WITH_REHEAT then
    local _, found_idx = tbl_contains(supported_modes, capabilities.thermostatMode.thermostatMode.precooling.NAME)
    if found_idx then
      table.remove(supported_modes, found_idx) -- if seen before, remove now
    end
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.heat.NAME)
    table.insert(disallowed_mode_operations, capabilities.thermostatMode.thermostatMode.cool.NAME)
    table.insert(disallowed_mode_operations, capabilities.thermostatMode.thermostatMode.precooling.NAME)
  elseif ib.data.value <= clusters.Thermostat.attributes.ControlSequenceOfOperation.COOLING_AND_HEATING_WITH_REHEAT then
    table.insert(modes_for_inclusion, capabilities.thermostatMode.thermostatMode.cool.NAME)
    table.insert(modes_for_inclusion, capabilities.thermostatMode.thermostatMode.heat.NAME)
  end

  -- check whether the Auto Mode should be supported in SystemMode, though this is unrelated to ControlSequenceOfOperation
  local auto = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.AUTOMODE})
  if #auto > 0 then
    table.insert(modes_for_inclusion, capabilities.thermostatMode.thermostatMode.auto.NAME)
  else
    table.insert(disallowed_mode_operations, capabilities.thermostatMode.thermostatMode.auto.NAME)
  end

  -- if a disallowed value was once allowed and added, it should be removed now.
  for index, mode in pairs(supported_modes) do
    if tbl_contains(disallowed_mode_operations, mode) then
      table.remove(supported_modes, index)
    end
  end
  -- do not include any values twice
  for _, mode in pairs(modes_for_inclusion) do
    if not tbl_contains(supported_modes, mode) then
      table.insert(supported_modes, mode)
    end
  end
  device:set_field(DISALLOWED_THERMOSTAT_MODES, disallowed_mode_operations)
  local event = capabilities.thermostatMode.supportedThermostatModes(supported_modes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)

  -- will be set by the SystemMode handler if this handler hasn't run yet.
  if device:get_field(SAVED_SYSTEM_MODE_IB) then
    system_mode_handler(driver, device, device:get_field(SAVED_SYSTEM_MODE_IB), response)
    device:set_field(SAVED_SYSTEM_MODE_IB, nil)
  end
end

local function min_deadband_limit_handler(driver, device, ib, response)
  local val = ib.data.value / 10.0
  log.info("Setting " .. setpoint_limit_device_field.MIN_DEADBAND .. " to " .. string.format("%s", val))
  device:set_field(setpoint_limit_device_field.MIN_DEADBAND, val, { persist = true })
  device:set_field(setpoint_limit_device_field.MIN_SETPOINT_DEADBAND_CHECKED, true, {persist = true})
end

local function fan_mode_handler(driver, device, ib, response)
  local fan_mode_event = {
    [clusters.FanControl.attributes.FanMode.OFF]    = { capabilities.fanMode.fanMode.off(),
                                                        capabilities.airConditionerFanMode.fanMode("off"),
                                                        capabilities.airPurifierFanMode.airPurifierFanMode.off(),
                                                        nil }, -- 'OFF' is not supported by thermostatFanMode
    [clusters.FanControl.attributes.FanMode.LOW]    = { capabilities.fanMode.fanMode.low(),
                                                        capabilities.airConditionerFanMode.fanMode("low"),
                                                        capabilities.airPurifierFanMode.airPurifierFanMode.low(),
                                                        capabilities.thermostatFanMode.thermostatFanMode.on() },
    [clusters.FanControl.attributes.FanMode.MEDIUM] = { capabilities.fanMode.fanMode.medium(),
                                                        capabilities.airConditionerFanMode.fanMode("medium"),
                                                        capabilities.airPurifierFanMode.airPurifierFanMode.medium(),
                                                        capabilities.thermostatFanMode.thermostatFanMode.on() },
    [clusters.FanControl.attributes.FanMode.HIGH]   = { capabilities.fanMode.fanMode.high(),
                                                        capabilities.airConditionerFanMode.fanMode("high"),
                                                        capabilities.airPurifierFanMode.airPurifierFanMode.high(),
                                                        capabilities.thermostatFanMode.thermostatFanMode.on() },
    [clusters.FanControl.attributes.FanMode.ON]     = { capabilities.fanMode.fanMode.auto(),
                                                        capabilities.airConditionerFanMode.fanMode("auto"),
                                                        capabilities.airPurifierFanMode.airPurifierFanMode.auto(),
                                                        capabilities.thermostatFanMode.thermostatFanMode.on() },
    [clusters.FanControl.attributes.FanMode.AUTO]   = { capabilities.fanMode.fanMode.auto(),
                                                        capabilities.airConditionerFanMode.fanMode("auto"),
                                                        capabilities.airPurifierFanMode.airPurifierFanMode.auto(),
                                                        capabilities.thermostatFanMode.thermostatFanMode.auto() },
    [clusters.FanControl.attributes.FanMode.SMART]  = { capabilities.fanMode.fanMode.auto(),
                                                        capabilities.airConditionerFanMode.fanMode("auto"),
                                                        capabilities.airPurifierFanMode.airPurifierFanMode.auto(),
                                                        capabilities.thermostatFanMode.thermostatFanMode.auto() }
  }
  local fan_mode_idx = device:supports_capability_by_id(capabilities.fanMode.ID) and 1 or
    device:supports_capability_by_id(capabilities.airConditionerFanMode.ID) and 2 or
    device:supports_capability_by_id(capabilities.airPurifierFanMode.ID) and 3 or
    device:supports_capability_by_id(capabilities.thermostatFanMode.ID) and 4
  if fan_mode_idx ~= false and fan_mode_event[ib.data.value][fan_mode_idx] then
    device:emit_event_for_endpoint(ib.endpoint_id, fan_mode_event[ib.data.value][fan_mode_idx])
  else
    log.warn(string.format("Invalid Fan Mode (%s)", ib.data.value))
  end
end

local function fan_mode_sequence_handler(driver, device, ib, response)
  local supported_fan_modes, supported_fan_modes_capability, supported_fan_modes_attribute
  if ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH then
    supported_fan_modes = { "off", "low", "medium", "high" }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH then
    supported_fan_modes = { "off", "low", "high" }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO then
    supported_fan_modes = { "off", "low", "medium", "high", "auto" }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH_AUTO then
    supported_fan_modes = { "off", "low", "high", "auto" }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_HIGH_AUTO then
    supported_fan_modes = { "off", "high", "auto" }
  else
    supported_fan_modes = { "off", "high" }
  end

  if device:supports_capability_by_id(capabilities.airPurifierFanMode.ID) then
    supported_fan_modes_capability = capabilities.airPurifierFanMode
    supported_fan_modes_attribute = supported_fan_modes_capability.supportedAirPurifierFanModes
  elseif device:supports_capability_by_id(capabilities.airConditionerFanMode.ID) then
    supported_fan_modes_capability = capabilities.airConditionerFanMode
    supported_fan_modes_attribute = supported_fan_modes_capability.supportedAcFanModes
  elseif device:supports_capability_by_id(capabilities.thermostatFanMode.ID) then
    supported_fan_modes_capability = capabilities.thermostatFanMode
    supported_fan_modes_attribute = capabilities.thermostatFanMode.supportedThermostatModes
    -- Our thermostat fan mode control is not granular enough to handle all of the supported modes
    if ib.data.value >= clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO and
      ib.data.value <= clusters.FanControl.attributes.FanModeSequence.OFF_ON_AUTO then
      supported_fan_modes = { "auto", "on" }
    else
      supported_fan_modes = { "on" }
    end
  else
    supported_fan_modes_capability = capabilities.fanMode
    supported_fan_modes_attribute = supported_fan_modes_capability.supportedFanModes
  end

  -- remove 'off' as a supported fan mode for thermostat device types, unless the
  -- device previously had 'off' as a supported fan mode to avoid breaking routines
  if get_device_type(device) == THERMOSTAT_DEVICE_TYPE_ID then
    local prev_supported_fan_modes = device:get_latest_state(
      device:endpoint_to_component(ib.endpoint_id),
      supported_fan_modes_capability.ID,
      supported_fan_modes_attribute.NAME
    ) or {}
    if not tbl_contains(prev_supported_fan_modes, "off") then
      local _, off_idx = tbl_contains(supported_fan_modes, "off")
      if off_idx then
        table.remove(supported_fan_modes, off_idx)
      end
    end
  end

  local event = supported_fan_modes_attribute(supported_fan_modes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function fan_speed_percent_attr_handler(driver, device, ib, response)
  local speed = 0
  if ib.data.value ~= nil then
    speed = utils.clamp_value(ib.data.value, MIN_ALLOWED_PERCENT_VALUE, MAX_ALLOWED_PERCENT_VALUE)
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanSpeedPercent.percent(speed))
end

local function wind_support_handler(driver, device, ib, response)
  local supported_wind_modes = {capabilities.windMode.windMode.noWind.NAME}
  for mode, wind_mode in pairs(WIND_MODE_MAP) do
    if ((ib.data.value >> mode) & 1) > 0 then
      table.insert(supported_wind_modes, wind_mode.NAME)
    end
  end
  local event = capabilities.windMode.supportedWindModes(supported_wind_modes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function wind_setting_handler(driver, device, ib, response)
  for index, wind_mode in pairs(WIND_MODE_MAP) do
    if ((ib.data.value >> index) & 1) > 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, wind_mode())
      return
    end
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windMode.windMode.noWind())
end

local function rock_support_handler(driver, device, ib, response)
  local supported_rock_modes = {capabilities.fanOscillationMode.fanOscillationMode.off.NAME}
  for mode, rock_mode in pairs(ROCK_MODE_MAP) do
    if ((ib.data.value >> mode) & 1) > 0 then
      table.insert(supported_rock_modes, rock_mode.NAME)
    end
  end
  local event = capabilities.fanOscillationMode.supportedFanOscillationModes(supported_rock_modes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function rock_setting_handler(driver, device, ib, response)
  for index, rock_mode in pairs(ROCK_MODE_MAP) do
    if ((ib.data.value >> index) & 1) > 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, rock_mode())
      return
    end
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanOscillationMode.fanOscillationMode.off())
end

local function hepa_filter_condition_handler(driver, device, ib, response)
  local component = device.profile.components["hepaFilter"]
  local condition = ib.data.value
  device:emit_component_event(component, capabilities.filterState.filterLifeRemaining(condition))
end

local function hepa_filter_change_indication_handler(driver, device, ib, response)
  local component = device.profile.components["hepaFilter"]
  if ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.OK then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.WARNING then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.CRITICAL then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.replace())
  end
end

local function activated_carbon_filter_condition_handler(driver, device, ib, response)
  local component = device.profile.components["activatedCarbonFilter"]
  local condition = ib.data.value
  device:emit_component_event(component, capabilities.filterState.filterLifeRemaining(condition))
end

local function activated_carbon_filter_change_indication_handler(driver, device, ib, response)
  local component = device.profile.components["activatedCarbonFilter"]
  if ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.OK then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.WARNING then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.CRITICAL then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.replace())
  end
end

local function handle_switch_on(driver, device, cmd)
  local endpoint_id = component_to_endpoint(device, cmd.component, clusters.OnOff.ID)
  local req = clusters.OnOff.server.commands.On(device, endpoint_id)
  device:send(req)
end

local function handle_switch_off(driver, device, cmd)
  local endpoint_id = component_to_endpoint(device, cmd.component, clusters.OnOff.ID)
  local req = clusters.OnOff.server.commands.Off(device, endpoint_id)
  device:send(req)
end

local function set_thermostat_mode(driver, device, cmd)
  local mode_id = nil
  for value, mode in pairs(THERMOSTAT_MODE_MAP) do
    if mode.NAME == cmd.args.mode then
      mode_id = value
      break
    end
  end
  if mode_id then
    device:send(clusters.Thermostat.attributes.SystemMode:write(device, component_to_endpoint(device, cmd.component, clusters.Thermostat.ID), mode_id))
  end
end

local thermostat_mode_setter = function(mode_name)
  return function(driver, device, cmd)
    return set_thermostat_mode(driver, device, {component = cmd.component, args = {mode = mode_name}})
  end
end

local function set_setpoint(setpoint)
  return function(driver, device, cmd)
    local endpoint_id = component_to_endpoint(device, cmd.component, clusters.Thermostat.ID)
    local MAX_TEMP_IN_C = THERMOSTAT_MAX_TEMP_IN_C
    local MIN_TEMP_IN_C = THERMOSTAT_MIN_TEMP_IN_C
    local is_water_heater_device = get_device_type(device) == WATER_HEATER_DEVICE_TYPE_ID
    if is_water_heater_device then
      MAX_TEMP_IN_C = WATER_HEATER_MAX_TEMP_IN_C
      MIN_TEMP_IN_C = WATER_HEATER_MIN_TEMP_IN_C
    end
    local value = cmd.args.setpoint
    if version.rpc <= 5 and value > MAX_TEMP_IN_C then
      value = utils.f_to_c(value)
    end

    -- Gather cached setpoint values when considering setpoint limits
    -- Note: cached values should always exist, but defaults are chosen just in case to prevent
    -- nil operation errors, and deadband logic from triggering.
    local cached_cooling_val, cooling_setpoint = device:get_latest_state(
      cmd.component, capabilities.thermostatCoolingSetpoint.ID,
      capabilities.thermostatCoolingSetpoint.coolingSetpoint.NAME,
      MAX_TEMP_IN_C, { value = MAX_TEMP_IN_C, unit = "C" }
    )
    if cooling_setpoint and cooling_setpoint.unit == "F" then
      cached_cooling_val = utils.f_to_c(cached_cooling_val)
    end
    local cached_heating_val, heating_setpoint = device:get_latest_state(
      cmd.component, capabilities.thermostatHeatingSetpoint.ID,
      capabilities.thermostatHeatingSetpoint.heatingSetpoint.NAME,
      MIN_TEMP_IN_C, { value = MIN_TEMP_IN_C, unit = "C" }
    )
    if heating_setpoint and heating_setpoint.unit == "F" then
      cached_heating_val = utils.f_to_c(cached_heating_val)
    end
    local is_auto_capable = #device:get_endpoints(
      clusters.Thermostat.ID,
      {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.AUTOMODE}
    ) > 0

    --Check setpoint limits for the device
    local setpoint_type = string.match(setpoint.NAME, "Heat") or "Cool"
    local deadband = device:get_field(setpoint_limit_device_field.MIN_DEADBAND) or 2.5 --spec default
    if setpoint_type == "Heat" then
      local min = device:get_field(setpoint_limit_device_field.MIN_HEAT) or MIN_TEMP_IN_C
      local max = device:get_field(setpoint_limit_device_field.MAX_HEAT) or MAX_TEMP_IN_C
      if value < min or value > max then
        log.warn(string.format(
          "Invalid setpoint (%s) outside the min (%s) and the max (%s)",
          value, min, max
        ))
        device:emit_event_for_endpoint(endpoint_id, capabilities.thermostatHeatingSetpoint.heatingSetpoint(heating_setpoint, {state_change = true}))
        return
      end
      if is_auto_capable and value > (cached_cooling_val - deadband) then
        log.warn(string.format(
          "Invalid setpoint (%s) is greater than the cooling setpoint (%s) with the deadband (%s)",
          value, cooling_setpoint, deadband
        ))
        device:emit_event_for_endpoint(endpoint_id, capabilities.thermostatHeatingSetpoint.heatingSetpoint(heating_setpoint, {state_change = true}))
        return
      end
    else
      local min = device:get_field(setpoint_limit_device_field.MIN_COOL) or MIN_TEMP_IN_C
      local max = device:get_field(setpoint_limit_device_field.MAX_COOL) or MAX_TEMP_IN_C
      if value < min or value > max then
        log.warn(string.format(
          "Invalid setpoint (%s) outside the min (%s) and the max (%s)",
          value, min, max
        ))
        device:emit_event_for_endpoint(endpoint_id, capabilities.thermostatCoolingSetpoint.coolingSetpoint(cooling_setpoint, {state_change = true}))
        return
      end
      if is_auto_capable and value < (cached_heating_val + deadband) then
        log.warn(string.format(
          "Invalid setpoint (%s) is less than the heating setpoint (%s) with the deadband (%s)",
          value, heating_setpoint, deadband
        ))
        device:emit_event_for_endpoint(endpoint_id, capabilities.thermostatCoolingSetpoint.coolingSetpoint(cooling_setpoint, {state_change = true}))
        return
      end
    end
    device:send(setpoint:write(device, component_to_endpoint(device, cmd.component, clusters.Thermostat.ID), utils.round(value * 100.0)))
  end
end

local heating_setpoint_limit_handler_factory = function(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local MAX_TEMP_IN_C = THERMOSTAT_MAX_TEMP_IN_C
    local MIN_TEMP_IN_C = THERMOSTAT_MIN_TEMP_IN_C
    local is_water_heater_device = (get_device_type(device) == WATER_HEATER_DEVICE_TYPE_ID)
    if is_water_heater_device then
      MAX_TEMP_IN_C = WATER_HEATER_MAX_TEMP_IN_C
      MIN_TEMP_IN_C = WATER_HEATER_MIN_TEMP_IN_C
    end
    local val = ib.data.value / 100.0
    val = utils.clamp_value(val, MIN_TEMP_IN_C, MAX_TEMP_IN_C)
    device:set_field(minOrMax, val)
    local min = device:get_field(setpoint_limit_device_field.MIN_HEAT)
    local max = device:get_field(setpoint_limit_device_field.MAX_HEAT)
    if min ~= nil and max ~= nil then
      if min < max then
        -- Only emit the capability for RPC version >= 5 (unit conversion for
        -- heating setpoint range capability is only supported for RPC >= 5)
        if version.rpc >= 5 then
          device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatHeatingSetpoint.heatingSetpointRange({ value = { minimum = min, maximum = max, step = 0.1 }, unit = "C" }))
        end
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min heating setpoint %d that is not lower than the reported max %d", min, max))
      end
    end
  end
end

local cooling_setpoint_limit_handler_factory = function(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local val = ib.data.value / 100.0
    val = utils.clamp_value(val, THERMOSTAT_MIN_TEMP_IN_C, THERMOSTAT_MAX_TEMP_IN_C)
    device:set_field(minOrMax, val)
    local min = device:get_field(setpoint_limit_device_field.MIN_COOL)
    local max = device:get_field(setpoint_limit_device_field.MAX_COOL)
    if min ~= nil and max ~= nil then
      if min < max then
        -- Only emit the capability for RPC version >= 5 (unit conversion for
        -- cooling setpoint range capability is only supported for RPC >= 5)
        if version.rpc >= 5 then
          device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatCoolingSetpoint.coolingSetpointRange({ value = { minimum = min, maximum = max, step = 0.1 }, unit = "C" }))
        end
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min cooling setpoint %d that is not lower than the reported max %d", min, max))
      end
    end
  end
end

local function set_fan_mode(device, cmd, fan_mode_capability)
  local command_argument = cmd.args.fanMode
  if fan_mode_capability == capabilities.airPurifierFanMode then
    command_argument = cmd.args.airPurifierFanMode
  elseif fan_mode_capability == capabilities.thermostatFanMode then
    command_argument = cmd.args.mode
  end
  local fan_mode_id
  if command_argument == "off" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.OFF
  elseif command_argument == "on" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.ON
  elseif command_argument == "auto" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.AUTO
  elseif command_argument == "high" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.HIGH
  elseif command_argument == "medium" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.MEDIUM
  elseif tbl_contains({ "low", "sleep", "quiet", "windFree" }, command_argument) then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  else
    device.log.warn(string.format("Invalid Fan Mode (%s) received from capability command", command_argument))
    return
  end
  device:send(clusters.FanControl.attributes.FanMode:write(device, component_to_endpoint(device, cmd.component, clusters.FanControl.ID), fan_mode_id))
end

local set_fan_mode_factory = function(fan_mode_capability)
  return function(driver, device, cmd)
    set_fan_mode(device, cmd, fan_mode_capability)
  end
end

local function thermostat_fan_mode_setter(mode_name)
  return function(driver, device, cmd)
    set_fan_mode(device, {component = cmd.component, args = {mode = mode_name}}, capabilities.thermostatFanMode)
  end
end

local function set_fan_speed_percent(driver, device, cmd)
  local speed = math.floor(cmd.args.percent)
  device:send(clusters.FanControl.attributes.PercentSetting:write(device, component_to_endpoint(device, cmd.component, clusters.FanControl.ID), speed))
end

local function set_wind_mode(driver, device, cmd)
  local wind_mode = 0
  if cmd.args.windMode == capabilities.windMode.windMode.sleepWind.NAME then
    wind_mode = clusters.FanControl.types.WindSupportMask.SLEEP_WIND
  elseif cmd.args.windMode == capabilities.windMode.windMode.naturalWind.NAME then
    wind_mode = clusters.FanControl.types.WindSupportMask.NATURAL_WIND
  end
  device:send(clusters.FanControl.attributes.WindSetting:write(device, component_to_endpoint(device, cmd.component, clusters.FanControl.ID), wind_mode))
end

local function set_rock_mode(driver, device, cmd)
  local rock_mode = 0
  if cmd.args.fanOscillationMode == capabilities.fanOscillationMode.fanOscillationMode.horizontal.NAME then
    rock_mode = clusters.FanControl.types.RockSupportMask.ROCK_LEFT_RIGHT
  elseif cmd.args.fanOscillationMode == capabilities.fanOscillationMode.fanOscillationMode.vertical.NAME then
    rock_mode = clusters.FanControl.types.RockSupportMask.ROCK_UP_DOWN
  elseif cmd.args.fanOscillationMode == capabilities.fanOscillationMode.fanOscillationMode.swing.NAME then
    rock_mode = clusters.FanControl.types.RockSupportMask.ROCK_ROUND
  end
  device:send(clusters.FanControl.attributes.RockSetting:write(device, component_to_endpoint(device, cmd.component, clusters.FanControl.ID), rock_mode))
end

local function set_water_heater_mode(driver, device, cmd)
  device.log.info(string.format("set_water_heater_mode mode: %s", cmd.args.mode))
  local endpoint_id = component_to_endpoint(device, cmd.component, clusters.Thermostat.ID)
  local supportedWaterHeaterModesWithIdx = device:get_field(SUPPORTED_WATER_HEATER_MODES_WITH_IDX) or {}
  for i, mode in ipairs(supportedWaterHeaterModesWithIdx) do
    if cmd.args.mode == mode[2] then
      device:send(clusters.WaterHeaterMode.commands.ChangeToMode(device, endpoint_id, mode[1]))
      return
    end
  end
end

local function reset_filter_state(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  if cmd.component == "hepaFilter" then
    device:send(clusters.HepaFilterMonitoring.server.commands.ResetCondition(device, endpoint_id))
  else
    device:send(clusters.ActivatedCarbonFilterMonitoring.server.commands.ResetCondition(device, endpoint_id))
  end
end

local function battery_percent_remaining_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

local function active_power_handler(driver, device, ib, response)
  if ib.data.value then
    local watt_value = ib.data.value / 1000
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.powerMeter.power({ value = watt_value, unit = "W" }))
    if type(device.register_native_capability_attr_handler) == "function" then
      device:register_native_capability_attr_handler("powerMeter","power")
    end
  end
end

local function periodic_energy_imported_handler(driver, device, ib, response)
  if ib.data then
    if version.api < 11 then
      clusters.ElectricalEnergyMeasurement.server.attributes.PeriodicEnergyImported:augment_type(ib.data)
    end
    local endpoint_id = string.format(ib.endpoint_id)
    local energy_imported_Wh = utils.round(ib.data.elements.energy.value / 1000) --convert mWh to Wh
    local cumulative_energy_imported = device:get_field(TOTAL_CUMULATIVE_ENERGY_IMPORTED_MAP) or {}
    cumulative_energy_imported[endpoint_id] = cumulative_energy_imported[endpoint_id] or 0
    cumulative_energy_imported[endpoint_id] = cumulative_energy_imported[endpoint_id] + energy_imported_Wh
    device:set_field(TOTAL_CUMULATIVE_ENERGY_IMPORTED_MAP, cumulative_energy_imported, { persist = true })
    local total_cumulative_energy_imported = get_total_cumulative_energy_imported(device)
    device:emit_component_event(device.profile.components["main"], ib.endpoint_id, capabilities.energyMeter.energy({value = total_cumulative_energy_imported, unit = "Wh"}))
    report_power_consumption_to_st_energy(device, total_cumulative_energy_imported)
  end
end

local function cumulative_energy_imported_handler(driver, device, ib, response)
  if ib.data then
    if version.api < 11 then
      clusters.ElectricalEnergyMeasurement.server.attributes.CumulativeEnergyImported:augment_type(ib.data)
    end
    local endpoint_id = string.format(ib.endpoint_id)
    local cumulative_energy_imported = device:get_field(TOTAL_CUMULATIVE_ENERGY_IMPORTED_MAP) or {}
    local cumulative_energy_imported_Wh = utils.round( ib.data.elements.energy.value / 1000) -- convert mWh to Wh
    cumulative_energy_imported[endpoint_id] = cumulative_energy_imported_Wh
    device:set_field(TOTAL_CUMULATIVE_ENERGY_IMPORTED_MAP, cumulative_energy_imported, { persist = true })
    local total_cumulative_energy_imported = get_total_cumulative_energy_imported(device)
    device:emit_component_event(device.profile.components["main"], capabilities.energyMeter.energy({ value = total_cumulative_energy_imported, unit = "Wh" }))
    report_power_consumption_to_st_energy(device, total_cumulative_energy_imported)
  end
end

local function energy_report_handler_factory(is_cumulative_report)
  return function(driver, device, ib, response)
    if is_cumulative_report then
      cumulative_energy_imported_handler(driver, device, ib, response)
    elseif device:get_field(CUMULATIVE_REPORTS_NOT_SUPPORTED) then
      periodic_energy_imported_handler(driver, device, ib, response)
    end
  end
end

local function water_heater_supported_modes_attr_handler(driver, device, ib, response)
  local supportWaterHeaterModes = {}
  local supportWaterHeaterModesWithIdx = {}
  for _, mode in ipairs(ib.data.elements) do
    if version.api < 13 then
      clusters.WaterHeaterMode.types.ModeOptionStruct:augment_type(mode)
    end
    table.insert(supportWaterHeaterModes, mode.elements.label.value)
    table.insert(supportWaterHeaterModesWithIdx, {mode.elements.mode.value, mode.elements.label.value})
  end
  device:set_field(SUPPORTED_WATER_HEATER_MODES_WITH_IDX, supportWaterHeaterModesWithIdx, { persist = true })
  local event = capabilities.mode.supportedModes(supportWaterHeaterModes, { visibility = { displayed = false } })
  device:emit_event_for_endpoint(ib.endpoint_id, event)
  event = capabilities.mode.supportedArguments(supportWaterHeaterModes, { visibility = { displayed = false } })
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function water_heater_mode_handler(driver, device, ib, response)
  device.log.info(string.format("water_heater_mode_handler mode: %s", ib.data.value))
  local supportWaterHeaterModesWithIdx = device:get_field(SUPPORTED_WATER_HEATER_MODES_WITH_IDX) or {}
  local currentMode = ib.data.value
  for i, mode in ipairs(supportWaterHeaterModesWithIdx) do
    if mode[1] == currentMode then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.mode(mode[2]))
      break
    end
  end
end

local function battery_charge_level_attr_handler(driver, device, ib, response)
  if ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.OK then
    device:emit_event(capabilities.batteryLevel.battery.normal())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.WARNING then
    device:emit_event(capabilities.batteryLevel.battery.warning())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.CRITICAL then
    device:emit_event(capabilities.batteryLevel.battery.critical())
  end
end

local function power_source_attribute_list_handler(driver, device, ib, response)
  for _, attr in ipairs(ib.data.elements) do
    -- mark if the device if BatPercentRemaining (Attribute ID 0x0C) or
    -- BatChargeLevel (Attribute ID 0x0E) is present and try profiling.
    if attr.value == 0x0C then
      device:set_field(profiling_data.BATTERY_SUPPORT, battery_support.BATTERY_PERCENTAGE)
      match_profile(driver, device)
      return
    elseif attr.value == 0x0E then
      device:set_field(profiling_data.BATTERY_SUPPORT, battery_support.BATTERY_LEVEL)
      match_profile(driver, device)
      return
    end
  end
end

local function thermostat_attribute_list_handler(driver, device, ib, response)
  for _, attr in ipairs(ib.data.elements) do
    -- mark whether the optional attribute ThermostatRunningState (0x029) is present and try profiling
    if attr.value == 0x029 then
      device:set_field(profiling_data.THERMOSTAT_RUNNING_STATE_SUPPORT, true)
      match_profile(driver, device)
      return
    end
  end
  device:set_field(profiling_data.THERMOSTAT_RUNNING_STATE_SUPPORT, false)
  match_profile(driver, device)
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    infoChanged = info_changed,
    removed = device_removed,
    driverSwitched = driver_switched
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.Thermostat.ID] = {
        [clusters.Thermostat.attributes.LocalTemperature.ID] = temp_event_handler(capabilities.temperatureMeasurement.temperature),
        [clusters.Thermostat.attributes.OccupiedCoolingSetpoint.ID] = temp_event_handler(capabilities.thermostatCoolingSetpoint.coolingSetpoint),
        [clusters.Thermostat.attributes.OccupiedHeatingSetpoint.ID] = temp_event_handler(capabilities.thermostatHeatingSetpoint.heatingSetpoint),
        [clusters.Thermostat.attributes.SystemMode.ID] = system_mode_handler,
        [clusters.Thermostat.attributes.ThermostatRunningState.ID] = running_state_handler,
        [clusters.Thermostat.attributes.ControlSequenceOfOperation.ID] = sequence_of_operation_handler,
        [clusters.Thermostat.attributes.AbsMinHeatSetpointLimit.ID] = heating_setpoint_limit_handler_factory(setpoint_limit_device_field.MIN_HEAT),
        [clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit.ID] = heating_setpoint_limit_handler_factory(setpoint_limit_device_field.MAX_HEAT),
        [clusters.Thermostat.attributes.AbsMinCoolSetpointLimit.ID] = cooling_setpoint_limit_handler_factory(setpoint_limit_device_field.MIN_COOL),
        [clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit.ID] = cooling_setpoint_limit_handler_factory(setpoint_limit_device_field.MAX_COOL),
        [clusters.Thermostat.attributes.MinSetpointDeadBand.ID] = min_deadband_limit_handler,
        [clusters.Thermostat.attributes.AttributeList.ID] = thermostat_attribute_list_handler,
      },
      [clusters.FanControl.ID] = {
        [clusters.FanControl.attributes.FanModeSequence.ID] = fan_mode_sequence_handler,
        [clusters.FanControl.attributes.FanMode.ID] = fan_mode_handler,
        [clusters.FanControl.attributes.PercentCurrent.ID] = fan_speed_percent_attr_handler,
        [clusters.FanControl.attributes.WindSupport.ID] = wind_support_handler,
        [clusters.FanControl.attributes.WindSetting.ID] = wind_setting_handler,
        [clusters.FanControl.attributes.RockSupport.ID] = rock_support_handler,
        [clusters.FanControl.attributes.RockSetting.ID] = rock_setting_handler,
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler(capabilities.temperatureMeasurement.temperature),
        [clusters.TemperatureMeasurement.attributes.MinMeasuredValue.ID] = temp_attr_handler_factory(setpoint_limit_device_field.MIN_TEMP),
        [clusters.TemperatureMeasurement.attributes.MaxMeasuredValue.ID] = temp_attr_handler_factory(setpoint_limit_device_field.MAX_TEMP),
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = humidity_attr_handler
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.AttributeList.ID] = power_source_attribute_list_handler,
        [clusters.PowerSource.attributes.BatChargeLevel.ID] = battery_charge_level_attr_handler,
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = battery_percent_remaining_attr_handler,
      },
      [clusters.HepaFilterMonitoring.ID] = {
        [clusters.HepaFilterMonitoring.attributes.Condition.ID] = hepa_filter_condition_handler,
        [clusters.HepaFilterMonitoring.attributes.ChangeIndication.ID] = hepa_filter_change_indication_handler
      },
      [clusters.ActivatedCarbonFilterMonitoring.ID] = {
        [clusters.ActivatedCarbonFilterMonitoring.attributes.Condition.ID] = activated_carbon_filter_condition_handler,
        [clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.ID] = activated_carbon_filter_change_indication_handler
      },
      [clusters.AirQuality.ID] = {
        [clusters.AirQuality.attributes.AirQuality.ID] = air_quality_attr_handler,
      },
      [clusters.CarbonMonoxideConcentrationMeasurement.ID] = {
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.carbonMonoxideMeasurement.NAME, capabilities.carbonMonoxideMeasurement.carbonMonoxideLevel, units.PPM),
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.carbonMonoxideMeasurement.NAME),
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.LevelValue.ID] = levelHandlerFactory(capabilities.carbonMonoxideHealthConcern.carbonMonoxideHealthConcern),
      },
      [clusters.CarbonDioxideConcentrationMeasurement.ID] = {
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.carbonDioxideMeasurement.NAME, capabilities.carbonDioxideMeasurement.carbonDioxide, units.PPM),
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.carbonDioxideMeasurement.NAME),
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.LevelValue.ID] = levelHandlerFactory(capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern),
      },
      [clusters.NitrogenDioxideConcentrationMeasurement.ID] = {
        [clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.nitrogenDioxideMeasurement.NAME, capabilities.nitrogenDioxideMeasurement.nitrogenDioxide, units.PPM),
        [clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.nitrogenDioxideMeasurement.NAME),
        [clusters.NitrogenDioxideConcentrationMeasurement.attributes.LevelValue.ID] = levelHandlerFactory(capabilities.nitrogenDioxideHealthConcern.nitrogenDioxideHealthConcern)
      },
      [clusters.OzoneConcentrationMeasurement.ID] = {
        [clusters.OzoneConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.ozoneMeasurement.NAME, capabilities.ozoneMeasurement.ozone, units.PPM),
        [clusters.OzoneConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.ozoneMeasurement.NAME),
        [clusters.OzoneConcentrationMeasurement.attributes.LevelValue.ID] = levelHandlerFactory(capabilities.ozoneHealthConcern.ozoneHealthConcern)
      },
      [clusters.FormaldehydeConcentrationMeasurement.ID] = {
        [clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.formaldehydeMeasurement.NAME, capabilities.formaldehydeMeasurement.formaldehydeLevel, units.PPM),
        [clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.formaldehydeMeasurement.NAME),
        [clusters.FormaldehydeConcentrationMeasurement.attributes.LevelValue.ID] = levelHandlerFactory(capabilities.formaldehydeHealthConcern.formaldehydeHealthConcern),
      },
      [clusters.Pm1ConcentrationMeasurement.ID] = {
        [clusters.Pm1ConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.veryFineDustSensor.NAME, capabilities.veryFineDustSensor.veryFineDustLevel, units.UGM3),
        [clusters.Pm1ConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.veryFineDustSensor.NAME),
        [clusters.Pm1ConcentrationMeasurement.attributes.LevelValue.ID] = levelHandlerFactory(capabilities.veryFineDustHealthConcern.veryFineDustHealthConcern),
      },
      [clusters.Pm25ConcentrationMeasurement.ID] = {
        [clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.fineDustSensor.NAME, capabilities.fineDustSensor.fineDustLevel, units.UGM3),
        [clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.fineDustSensor.NAME),
        [clusters.Pm25ConcentrationMeasurement.attributes.LevelValue.ID] = levelHandlerFactory(capabilities.fineDustHealthConcern.fineDustHealthConcern),
      },
      [clusters.Pm10ConcentrationMeasurement.ID] = {
        [clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.dustSensor.NAME, capabilities.dustSensor.dustLevel, units.UGM3),
        [clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.dustSensor.NAME),
        [clusters.Pm10ConcentrationMeasurement.attributes.LevelValue.ID] = levelHandlerFactory(capabilities.dustHealthConcern.dustHealthConcern),
      },
      [clusters.RadonConcentrationMeasurement.ID] = {
        [clusters.RadonConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.radonMeasurement.NAME, capabilities.radonMeasurement.radonLevel, units.PCIL),
        [clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.radonMeasurement.NAME),
        [clusters.RadonConcentrationMeasurement.attributes.LevelValue.ID] = levelHandlerFactory(capabilities.radonHealthConcern.radonHealthConcern)
      },
      [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID] = {
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.tvocMeasurement.NAME, capabilities.tvocMeasurement.tvocLevel, units.PPB),
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.tvocMeasurement.NAME),
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue.ID] = levelHandlerFactory(capabilities.tvocHealthConcern.tvocHealthConcern)
      },
      [clusters.ElectricalPowerMeasurement.ID] = {
        [clusters.ElectricalPowerMeasurement.attributes.ActivePower.ID] = active_power_handler
      },
      [clusters.ElectricalEnergyMeasurement.ID] = {
        [clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported.ID] = energy_report_handler_factory(true),
        [clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported.ID] = energy_report_handler_factory(false),
      },
      [clusters.WaterHeaterMode.ID] = {
        [clusters.WaterHeaterMode.attributes.CurrentMode.ID] = water_heater_mode_handler,
        [clusters.WaterHeaterMode.attributes.SupportedModes.ID] = water_heater_supported_modes_attr_handler
      },
    },
  },
  subscribed_attributes = subscribed_attributes,
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = set_thermostat_mode,
      [capabilities.thermostatMode.commands.auto.NAME] = thermostat_mode_setter(capabilities.thermostatMode.thermostatMode.auto.NAME),
      [capabilities.thermostatMode.commands.off.NAME] = thermostat_mode_setter(capabilities.thermostatMode.thermostatMode.off.NAME),
      [capabilities.thermostatMode.commands.cool.NAME] = thermostat_mode_setter(capabilities.thermostatMode.thermostatMode.cool.NAME),
      [capabilities.thermostatMode.commands.heat.NAME] = thermostat_mode_setter(capabilities.thermostatMode.thermostatMode.heat.NAME),
      [capabilities.thermostatMode.commands.emergencyHeat.NAME] = thermostat_mode_setter(capabilities.thermostatMode.thermostatMode.emergency_heat.NAME)
    },
    [capabilities.thermostatFanMode.ID] = {
      [capabilities.thermostatFanMode.commands.setThermostatFanMode.NAME] = set_fan_mode_factory(capabilities.thermostatFanMode),
      [capabilities.thermostatFanMode.commands.fanAuto.NAME] = thermostat_fan_mode_setter(capabilities.thermostatFanMode.thermostatFanMode.auto.NAME),
      [capabilities.thermostatFanMode.commands.fanOn.NAME] = thermostat_fan_mode_setter(capabilities.thermostatFanMode.thermostatFanMode.on.NAME)
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = set_setpoint(clusters.Thermostat.attributes.OccupiedCoolingSetpoint)
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_setpoint(clusters.Thermostat.attributes.OccupiedHeatingSetpoint)
    },
    [capabilities.airConditionerFanMode.ID] = {
      [capabilities.airConditionerFanMode.commands.setFanMode.NAME] = set_fan_mode_factory(capabilities.airConditionerFanMode)
    },
    [capabilities.airPurifierFanMode.ID] = {
      [capabilities.airPurifierFanMode.commands.setAirPurifierFanMode.NAME] = set_fan_mode_factory(capabilities.airPurifierFanMode)
    },
    [capabilities.fanMode.ID] = {
      [capabilities.fanMode.commands.setFanMode.NAME] = set_fan_mode_factory(capabilities.fanMode)
    },
    [capabilities.fanSpeedPercent.ID] = {
      [capabilities.fanSpeedPercent.commands.setPercent.NAME] = set_fan_speed_percent,
    },
    [capabilities.windMode.ID] = {
      [capabilities.windMode.commands.setWindMode.NAME] = set_wind_mode,
    },
    [capabilities.fanOscillationMode.ID] = {
      [capabilities.fanOscillationMode.commands.setFanOscillationMode.NAME] = set_rock_mode,
    },
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = set_water_heater_mode,
    },
    [capabilities.filterState.ID] = {
      [capabilities.filterState.commands.resetFilter.NAME] = reset_filter_state,
    }
  },
  supported_capabilities = {
    capabilities.thermostatMode,
    capabilities.thermostatHeatingSetpoint,
    capabilities.thermostatCoolingSetpoint,
    capabilities.thermostatFanMode,
    capabilities.thermostatOperatingState,
    capabilities.airConditionerFanMode,
    capabilities.fanMode,
    capabilities.fanSpeedPercent,
    capabilities.airPurifierFanMode,
    capabilities.windMode,
    capabilities.fanOscillationMode,
    capabilities.battery,
    capabilities.batteryLevel,
    capabilities.filterState,
    capabilities.filterStatus,
    capabilities.airQualityHealthConcern,
    capabilities.carbonDioxideHealthConcern,
    capabilities.carbonDioxideMeasurement,
    capabilities.carbonMonoxideHealthConcern,
    capabilities.carbonMonoxideMeasurement,
    capabilities.nitrogenDioxideHealthConcern,
    capabilities.nitrogenDioxideMeasurement,
    capabilities.ozoneHealthConcern,
    capabilities.ozoneMeasurement,
    capabilities.formaldehydeHealthConcern,
    capabilities.formaldehydeMeasurement,
    capabilities.veryFineDustHealthConcern,
    capabilities.veryFineDustSensor,
    capabilities.fineDustHealthConcern,
    capabilities.fineDustSensor,
    capabilities.dustSensor,
    capabilities.dustHealthConcern,
    capabilities.radonHealthConcern,
    capabilities.radonMeasurement,
    capabilities.tvocHealthConcern,
    capabilities.tvocMeasurement,
    capabilities.powerMeter,
    capabilities.energyMeter,
    capabilities.powerConsumptionReport,
    capabilities.mode
  },
}

local matter_driver = MatterDriver("matter-thermostat", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
