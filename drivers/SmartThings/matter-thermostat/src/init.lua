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

-- Include driver-side definitions when lua libs api version is < 10
local version = require "version"
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

local DISALLOWED_THERMOSTAT_MODES = "__DISALLOWED_CONTROL_OPERATIONS"

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
  [0]		= capabilities.thermostatOperatingState.thermostatOperatingState.heating,
  [1]		= capabilities.thermostatOperatingState.thermostatOperatingState.cooling,
  [2]		= capabilities.thermostatOperatingState.thermostatOperatingState.fan_only,
  [3]		= capabilities.thermostatOperatingState.thermostatOperatingState.heating,
  [4]		= capabilities.thermostatOperatingState.thermostatOperatingState.cooling,
  [5]		= capabilities.thermostatOperatingState.thermostatOperatingState.fan_only,
  [6]		= capabilities.thermostatOperatingState.thermostatOperatingState.fan_only,
}

local WIND_MODE_MAP = {
  [0]		= capabilities.windMode.windMode.sleepWind,
  [1]		= capabilities.windMode.windMode.naturalWind
}

local ROCK_MODE_MAP = {
  [0] = capabilities.fanOscillationMode.fanOscillationMode.horizontal,
  [1] = capabilities.fanOscillationMode.fanOscillationMode.vertical,
  [2] = capabilities.fanOscillationMode.fanOscillationMode.swing
}

local RAC_DEVICE_TYPE_ID = 0x0072
local AP_DEVICE_TYPE_ID = 0x002D
local FAN_DEVICE_TYPE_ID = 0x002B

local MIN_ALLOWED_PERCENT_VALUE = 0
local MAX_ALLOWED_PERCENT_VALUE = 100

local MGM3_PPM_CONVERSION_FACTOR = 24.45

-- This is a work around to handle when units for temperatureSetpoint is changed for the App.
-- When units are switched, we will never know the units of the received command value as the arguments don't contain the unit.
-- So to handle this we assume the following ranges considering usual laundry temperatures:
--   1. if the received setpoint command value is in range 5 ~ 40, it is inferred as *C
--   2. if the received setpoint command value is in range 41 ~ 104, it is inferred as *F
local THERMOSTAT_MAX_TEMP_IN_C = 40.0
local THERMOSTAT_MIN_TEMP_IN_C = 5.0

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
    clusters.FanControl.attributes.FanMode
  },
  [capabilities.airPurifierFanMode.ID] = {
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
  }
}

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

local function component_to_endpoint(device, component_name)
  -- Use the find_default_endpoint function to return the first endpoint that
  -- supports a given cluster.
  if device:supports_capability(capabilities.airPurifierFanMode) then
    -- Fan Control is mandatory for the Air Purifier device type
    return find_default_endpoint(device, clusters.FanControl.ID)
  else
    -- Thermostat is mandatory for Thermostat and Room AC device type
    return find_default_endpoint(device, clusters.Thermostat.ID)
  end
end

local function device_init(driver, device)
  device:subscribe()
  device:set_component_to_endpoint_fn(component_to_endpoint)
  if not device:get_field(setpoint_limit_device_field.MIN_SETPOINT_DEADBAND_CHECKED) then
    local auto_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.AUTOMODE})
    --Query min setpoint deadband if needed
    if #auto_eps ~= 0 and device:get_field(setpoint_limit_device_field.MIN_DEADBAND) == nil then
      local deadband_read = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
      deadband_read:merge(clusters.Thermostat.attributes.MinSetpointDeadBand:read())
      device:send(deadband_read)
    end
  end
end

local function info_changed(driver, device, event, args)
  --Note this is needed because device:subscribe() does not recalculate
  -- the subscribed attributes each time it is run, that only happens at init.
  -- This will change in the 0.48.x release of the lua libs.
  for cap_id, attributes in pairs(subscribed_attributes) do
    if device:supports_capability_by_id(cap_id) then
      for _, attr in ipairs(attributes) do
        device:add_subscribed_attribute(attr)
      end
    end
  end
  device:subscribe()
end

local function get_device_type(driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == RAC_DEVICE_TYPE_ID then
        return RAC_DEVICE_TYPE_ID
      elseif dt.device_type_id == AP_DEVICE_TYPE_ID then
        return AP_DEVICE_TYPE_ID
      elseif dt.device_type_id == FAN_DEVICE_TYPE_ID then
        return FAN_DEVICE_TYPE_ID
      end
    end
  end
  return false
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
    device.log.warn_with({hub_logs=true}, "Device does not support either heating or cooling. No matching profile")
    return "No Heating nor Cooling Support"
  elseif #heat_eps > 0 and #cool_eps == 0 then
    thermostat_modes = thermostat_modes .. "-heating-only"
  elseif #cool_eps > 0 and #heat_eps == 0 then
    thermostat_modes = thermostat_modes .. "-cooling-only"
  end
  return thermostat_modes
end

local function match_profile(driver, device, battery_supported)
  local thermostat_eps = device:get_endpoints(clusters.Thermostat.ID)
  local humidity_eps = device:get_endpoints(clusters.RelativeHumidityMeasurement.ID)
  local device_type = get_device_type(driver, device)
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
      if thermostat_modes == "No Heating nor Cooling Support" then
        return
      else
        profile_name = profile_name .. thermostat_modes
      end

      profile_name = profile_name .. "-nostate"

      if battery_supported == battery_support.BATTERY_LEVEL then
        profile_name = profile_name .. "-batteryLevel"
      elseif battery_supported == battery_support.NO_BATTERY then
        profile_name = profile_name .. "-nobattery"
      end
    end
    profile_name = profile_name .. create_air_quality_sensor_profile(device)

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
      return
    else
      profile_name = profile_name .. thermostat_modes
    end

    -- TODO remove this in favor of reading Thermostat clusters AttributeList attribute
    -- to determine support for ThermostatRunningState
    -- Add nobattery profiles if updated
    profile_name = profile_name .. "-nostate"

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
end

local function do_configure(driver, device)
  local battery_feature_eps = device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
  if #battery_feature_eps > 0 then
    local req = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
    req:merge(clusters.PowerSource.attributes.AttributeList:read())
    device:send(req)
  else
    match_profile(driver, device, battery_support.NO_BATTERY)
  end
end

local function device_added(driver, device)
  local req = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  req:merge(clusters.Thermostat.attributes.ControlSequenceOfOperation:read(device))
  req:merge(clusters.FanControl.attributes.FanModeSequence:read(device))
  req:merge(clusters.FanControl.attributes.WindSupport:read(device))
  req:merge(clusters.FanControl.attributes.RockSupport:read(device))
  device:send(req)
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
        local range = {
          minimum = device:get_field(setpoint_limit_device_field.MIN_HEAT) or THERMOSTAT_MIN_TEMP_IN_C,
          maximum = device:get_field(setpoint_limit_device_field.MAX_HEAT) or THERMOSTAT_MAX_TEMP_IN_C,
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
  local supported_modes = device:get_latest_state(device:endpoint_to_component(ib.endpoint_id), capabilities.thermostatMode.ID, capabilities.thermostatMode.supportedThermostatModes.NAME) or {}
  -- check that the given mode was in the supported modes list
  for _, mode in ipairs(supported_modes) do
    if mode == THERMOSTAT_MODE_MAP[ib.data.value].NAME then
      device:emit_event_for_endpoint(ib.endpoint_id, THERMOSTAT_MODE_MAP[ib.data.value]())
      return
    end
  end
  -- if the value is not found in the supported modes list, check if it's disallowed
  local disallowed_thermostat_modes = device:get_field(DISALLOWED_THERMOSTAT_MODES) or {}
  for _, mode in pairs(disallowed_thermostat_modes) do
    if mode == ib.data.value then
      return
    end
  end
  -- if we get here, then the reported mode is allowed and not in our mode map
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
  -- The ControlSequenceofOperation attribute only directly specifies what can't be operated by the operating environment, not what can.
  -- However, we assert here that a Cooling enum value implies that SystemMode supports cooling, and the same for a Heating enum.
  -- We also assert that Off is supported, though per spec this is optional.
  local disallowed_mode_operations = {}
  local supported_modes = {capabilities.thermostatMode.thermostatMode.off.NAME}

  if ib.data.value <= clusters.Thermostat.attributes.ControlSequenceOfOperation.COOLING_WITH_REHEAT then
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.cool.NAME)
    table.insert(disallowed_mode_operations, clusters.Thermostat.types.ThermostatSystemMode.HEAT)
    table.insert(disallowed_mode_operations, clusters.Thermostat.types.ThermostatSystemMode.EMERGENCY_HEATING)
  elseif ib.data.value <= clusters.Thermostat.attributes.ControlSequenceOfOperation.HEATING_WITH_REHEAT then
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.heat.NAME)
    table.insert(disallowed_mode_operations, clusters.Thermostat.types.ThermostatSystemMode.COOL)
    table.insert(disallowed_mode_operations, clusters.Thermostat.types.ThermostatSystemMode.PRECOOLING)
  elseif ib.data.value <= clusters.Thermostat.attributes.ControlSequenceOfOperation.COOLING_AND_HEATING_WITH_REHEAT then
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.cool.NAME)
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.heat.NAME)
  end

  -- check whether the Auto Mode should be supported in SystemMode, though this is unrelated to ControlSequenceofOperation
  local auto = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.AUTOMODE})
  if #auto > 0 then
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.auto.NAME)
  else
    table.insert(disallowed_mode_operations, clusters.Thermostat.types.ThermostatSystemMode.AUTO)
  end

  device:set_field(DISALLOWED_THERMOSTAT_MODES, disallowed_mode_operations, {persist = true})
  local event = capabilities.thermostatMode.supportedThermostatModes(supported_modes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function min_deadband_limit_handler(driver, device, ib, response)
  local val = ib.data.value / 10.0
  log.info("Setting " .. setpoint_limit_device_field.MIN_DEADBAND .. " to " .. string.format("%s", val))
  device:set_field(setpoint_limit_device_field.MIN_DEADBAND, val, { persist = true })
  device:set_field(setpoint_limit_device_field.MIN_SETPOINT_DEADBAND_CHECKED, true, {persist = true})
end

local function fan_mode_handler(driver, device, ib, response)
  if device:supports_capability_by_id(capabilities.airConditionerFanMode.ID) then
    -- Room Air Conditioner
    if ib.data.value == clusters.FanControl.attributes.FanMode.OFF then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airConditionerFanMode.fanMode("off"))
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.LOW then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airConditionerFanMode.fanMode("low"))
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.MEDIUM then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airConditionerFanMode.fanMode("medium"))
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.HIGH then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airConditionerFanMode.fanMode("high"))
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airConditionerFanMode.fanMode("auto"))
    end
  elseif device:supports_capability_by_id(capabilities.airPurifierFanMode.ID) then
    if ib.data.value == clusters.FanControl.attributes.FanMode.OFF then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.off())
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.LOW then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.low())
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.MEDIUM then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.medium())
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.HIGH then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.high())
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.auto())
    end
  else
    -- Thermostat
    if ib.data.value == clusters.FanControl.attributes.FanMode.AUTO or
      ib.data.value == clusters.FanControl.attributes.FanMode.SMART then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatFanMode.thermostatFanMode.auto())
    elseif ib.data.value ~= clusters.FanControl.attributes.FanMode.OFF then -- we don't have an "off" value
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatFanMode.thermostatFanMode.on())
    end
  end
end

local function fan_mode_sequence_handler(driver, device, ib, response)
  if device:supports_capability_by_id(capabilities.airConditionerFanMode.ID) then
    -- Room Air Conditioner
    local supportedAcFanModes
    if ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH then
      supportedAcFanModes = {
        "off",
        "low",
        "medium",
        "high"
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH then
      supportedAcFanModes = {
        "off",
        "low",
        "high"
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO then
      supportedAcFanModes = {
        "off",
        "low",
        "medium",
        "high",
        "auto"
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH_AUTO then
      supportedAcFanModes = {
        "off",
        "low",
        "high",
        "auto"
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_ON_AUTO then
      supportedAcFanModes = {
        "off",
        "high",
        "auto"
      }
    else
      supportedAcFanModes = {
        "off",
        "high"
      }
    end
    local event = capabilities.airConditionerFanMode.supportedAcFanModes(supportedAcFanModes, {visibility = {displayed = false}})
    device:emit_event_for_endpoint(ib.endpoint_id, event)
  elseif device:supports_capability_by_id(capabilities.airPurifierFanMode.ID) then
    -- Air Purifier
    local supportedAirPurifierFanModes
    if ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH then
      supportedAirPurifierFanModes = {
        capabilities.airPurifierFanMode.airPurifierFanMode.off.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.medium.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH then
      supportedAirPurifierFanModes = {
        capabilities.airPurifierFanMode.airPurifierFanMode.off.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO then
      supportedAirPurifierFanModes = {
        capabilities.airPurifierFanMode.airPurifierFanMode.off.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.medium.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.auto.NAME
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH_AUTO then
      supportedAirPurifierFanModes = {
        capabilities.airPurifierFanMode.airPurifierFanMode.off.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.auto.NAME
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_ON_AUTO then
      supportedAirPurifierFanModes = {
        capabilities.airPurifierFanMode.airPurifierFanMode.off.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.auto.NAME
      }
    else
      supportedAirPurifierFanModes = {
        capabilities.airPurifierFanMode.airPurifierFanMode.off.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME
      }
    end
    local event = capabilities.airPurifierFanMode.supportedAirPurifierFanModes(supportedAirPurifierFanModes, {visibility = {displayed = false}})
    device:emit_event_for_endpoint(ib.endpoint_id, event)
  else
    -- Thermostat
    -- Our thermostat fan mode control is probably not granular enough to handle the supported modes here well
    -- definitely meant for actual fans and not HVAC fans
    if ib.data.value >= clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO and
      ib.data.value <= clusters.FanControl.attributes.FanModeSequence.OFF_ON_AUTO then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatFanMode.supportedThermostatFanModes(
        {capabilities.thermostatFanMode.thermostatFanMode.auto.NAME, capabilities.thermostatFanMode.thermostatFanMode.on.NAME},
        {visibility = {displayed = false}}
      ))
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatFanMode.supportedThermostatFanModes(
        {capabilities.thermostatFanMode.thermostatFanMode.on.NAME},
        {visibility = {displayed = false}}
      ))
    end
  end
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
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.On(device, endpoint_id)
  device:send(req)
end

local function handle_switch_off(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
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
    device:send(clusters.Thermostat.attributes.SystemMode:write(device, device:component_to_endpoint(cmd.component), mode_id))
  end
end

local thermostat_mode_setter = function(mode_name)
  return function(driver, device, cmd)
    return set_thermostat_mode(driver, device, {component = cmd.component, args = {mode = mode_name}})
  end
end

local function set_setpoint(setpoint)
  return function(driver, device, cmd)
    local value = cmd.args.setpoint
    if (value > THERMOSTAT_MAX_TEMP_IN_C) then -- assume this is a fahrenheit value
      value = utils.f_to_c(value)
    end

    -- Gather cached setpoint values when considering setpoint limits
    -- Note: cached values should always exist, but defaults are chosen just in case to prevent
    -- nil operation errors, and deadband logic from triggering.
    local cached_cooling_val, cooling_setpoint = device:get_latest_state(
      cmd.component, capabilities.thermostatCoolingSetpoint.ID,
      capabilities.thermostatCoolingSetpoint.coolingSetpoint.NAME,
      THERMOSTAT_MAX_TEMP_IN_C, { value = THERMOSTAT_MAX_TEMP_IN_C, unit = "C" }
    )
    if cooling_setpoint and cooling_setpoint.unit == "F" then
      cached_cooling_val = utils.f_to_c(cached_cooling_val)
    end
    local cached_heating_val, heating_setpoint = device:get_latest_state(
      cmd.component, capabilities.thermostatHeatingSetpoint.ID,
      capabilities.thermostatHeatingSetpoint.heatingSetpoint.NAME,
      THERMOSTAT_MIN_TEMP_IN_C, { value = THERMOSTAT_MIN_TEMP_IN_C, unit = "C" }
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
      local min = device:get_field(setpoint_limit_device_field.MIN_HEAT) or THERMOSTAT_MIN_TEMP_IN_C
      local max = device:get_field(setpoint_limit_device_field.MAX_HEAT) or THERMOSTAT_MAX_TEMP_IN_C
      if value < min or value > max then
        log.warn(string.format(
          "Invalid setpoint (%s) outside the min (%s) and the max (%s)",
          value, min, max
        ))
        device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint(heating_setpoint, {state_change = true}))
        return
      end
      if is_auto_capable and value > (cached_cooling_val - deadband) then
        log.warn(string.format(
          "Invalid setpoint (%s) is greater than the cooling setpoint (%s) with the deadband (%s)",
          value, cooling_setpoint, deadband
        ))
        device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint(heating_setpoint, {state_change = true}))
        return
      end
    else
      local min = device:get_field(setpoint_limit_device_field.MIN_COOL) or THERMOSTAT_MIN_TEMP_IN_C
      local max = device:get_field(setpoint_limit_device_field.MAX_COOL) or THERMOSTAT_MAX_TEMP_IN_C
      if value < min or value > max then
        log.warn(string.format(
          "Invalid setpoint (%s) outside the min (%s) and the max (%s)",
          value, min, max
        ))
        device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint(cooling_setpoint, {state_change = true}))
        return
      end
      if is_auto_capable and value < (cached_heating_val + deadband) then
        log.warn(string.format(
          "Invalid setpoint (%s) is less than the heating setpoint (%s) with the deadband (%s)",
          value, heating_setpoint, deadband
        ))
        device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint(cooling_setpoint, {state_change = true}))
        return
      end
    end
    device:send(setpoint:write(device, device:component_to_endpoint(cmd.component), utils.round(value * 100.0)))
  end
end

local heating_setpoint_limit_handler_factory = function(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local val = ib.data.value / 100.0
    val = utils.clamp_value(val, THERMOSTAT_MIN_TEMP_IN_C, THERMOSTAT_MAX_TEMP_IN_C)
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

local function set_thermostat_fan_mode(driver, device, cmd)
  local fan_mode_id = nil
  if cmd.args.mode == capabilities.thermostatFanMode.thermostatFanMode.auto.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.AUTO
  elseif cmd.args.mode == capabilities.thermostatFanMode.thermostatFanMode.on.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.ON
  end
  if fan_mode_id then
    device:send(clusters.FanControl.attributes.FanMode:write(device, device:component_to_endpoint(cmd.component), fan_mode_id))
  end
end

local function thermostat_fan_mode_setter(mode_name)
  return function(driver, device, cmd)
    return set_thermostat_fan_mode(driver, device, {component = cmd.component, args = {mode = mode_name}})
  end
end

local function set_fan_mode(driver, device, cmd)
  local fan_mode_id
  if cmd.args.fanMode == "off" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.OFF
  elseif cmd.args.fanMode == "low" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.fanMode == "medium" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.MEDIUM
  elseif cmd.args.fanMode == "high" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.HIGH
  elseif cmd.args.fanMode == "auto" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.AUTO
  else
    fan_mode_id = clusters.FanControl.attributes.FanMode.OFF
  end
  if fan_mode_id then
    device:send(clusters.FanControl.attributes.FanMode:write(device, device:component_to_endpoint(cmd.component), fan_mode_id))
  end
end

local function set_air_purifier_fan_mode(driver, device, cmd)
  local fan_mode_id
  if cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.sleep.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.quiet.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.windFree.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.medium.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.MEDIUM
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.HIGH
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.auto.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.AUTO
  else
    fan_mode_id = clusters.FanControl.attributes.FanMode.OFF
  end
  if fan_mode_id then
    device:send(clusters.FanControl.attributes.FanMode:write(device, device:component_to_endpoint(cmd.component), fan_mode_id))
  end
end

local function set_fan_speed_percent(driver, device, cmd)
  local speed = math.floor(cmd.args.percent)
  device:send(clusters.FanControl.attributes.PercentSetting:write(device, device:component_to_endpoint(cmd.component), speed))
end

local function set_wind_mode(driver, device, cmd)
  local wind_mode = 0
  if cmd.args.windMode == capabilities.windMode.windMode.sleepWind.NAME then
    wind_mode = clusters.FanControl.types.WindSupportMask.SLEEP_WIND
  elseif cmd.args.windMode == capabilities.windMode.windMode.naturalWind.NAME then
    wind_mode = clusters.FanControl.types.WindSupportMask.NATURAL_WIND
  end
  device:send(clusters.FanControl.attributes.WindSetting:write(device, device:component_to_endpoint(cmd.component), wind_mode))
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
  device:send(clusters.FanControl.attributes.RockSetting:write(device, device:component_to_endpoint(cmd.component), rock_mode))
end

local function battery_percent_remaining_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
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
    -- Re-profile the device if BatPercentRemaining (Attribute ID 0x0C) or
    -- BatChargeLevel (Attribute ID 0x0E) is present.
    if attr.value == 0x0C then
      match_profile(driver, device, battery_support.BATTERY_PERCENTAGE)
      return
    elseif attr.value == 0x0E then
      match_profile(driver, device, battery_support.BATTERY_LEVEL)
      return
    end
  end
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    infoChanged = info_changed,
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
      }
    }
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
      [capabilities.thermostatFanMode.commands.setThermostatFanMode.NAME] = set_thermostat_fan_mode,
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
      [capabilities.airConditionerFanMode.commands.setFanMode.NAME] = set_fan_mode,
    },
    [capabilities.airPurifierFanMode.ID] = {
      [capabilities.airPurifierFanMode.commands.setAirPurifierFanMode.NAME] = set_air_purifier_fan_mode
    },
    [capabilities.fanSpeedPercent.ID] = {
      [capabilities.fanSpeedPercent.commands.setPercent.NAME] = set_fan_speed_percent,
    },
    [capabilities.windMode.ID] = {
      [capabilities.windMode.commands.setWindMode.NAME] = set_wind_mode,
    },
    [capabilities.fanOscillationMode.ID] = {
      [capabilities.fanOscillationMode.commands.setFanOscillationMode.NAME] = set_rock_mode,
    }
  },
  supported_capabilities = {
    capabilities.thermostatMode,
    capabilities.thermostatHeatingSetpoint,
    capabilities.thermostatCoolingSetpoint,
    capabilities.thermostatFanMode,
    capabilities.thermostatOperatingState,
    capabilities.airConditionerFanMode,
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
    capabilities.tvocMeasurement
  },
}

local matter_driver = MatterDriver("matter-thermostat", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()