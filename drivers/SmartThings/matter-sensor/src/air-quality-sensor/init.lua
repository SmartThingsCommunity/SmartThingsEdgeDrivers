-- Copyright 2024 SmartThings
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
local clusters = require "st.matter.clusters"
local utils = require "st.utils"
local embedded_cluster_utils = require "embedded-cluster-utils"

local log = require "log"
local AIR_QUALITY_SENSOR_DEVICE_TYPE_ID = 0x002C

-- Include driver-side definitions when lua libs api version is < 10
local version = require "version"
if version.api < 10 then
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
end

local function is_matter_air_quality_sensor(opts, driver, device)
    for _, ep in ipairs(device.endpoints) do
      for _, dt in ipairs(ep.device_types) do
        if dt.device_type_id == AIR_QUALITY_SENSOR_DEVICE_TYPE_ID then
          return true
        end
      end
    end

    return false
  end

local subscribed_attributes = {
  [capabilities.airQualityHealthConcern.ID] = {
    clusters.AirQuality.attributes.AirQuality
  },
  [capabilities.temperatureMeasurement.ID] = {
    clusters.TemperatureMeasurement.attributes.MeasuredValue
  },
  [capabilities.relativeHumidityMeasurement.ID] = {
    clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
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

local units_required = {
  clusters.CarbonMonoxideConcentrationMeasurement,
  clusters.CarbonDioxideConcentrationMeasurement,
  clusters.NitrogenDioxideConcentrationMeasurement,
  clusters.OzoneConcentrationMeasurement,
  clusters.FormaldehydeConcentrationMeasurement,
  clusters.Pm1ConcentrationMeasurement,
  clusters.Pm25ConcentrationMeasurement,
  clusters.Pm10ConcentrationMeasurement,
  clusters.RadonConcentrationMeasurement,
  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement
}

local function device_init(driver, device)
  device:subscribe()
end

local tbl_contains = function(t, val)
  for _, v in pairs(t) do
    if v == val then
      return true
    end
  end
  return false
end

local supported_profiles =
{
  "aqs",
  "aqs-temp-humidity-all-level-all-meas",
  "aqs-temp-humidity-all-level",
  "aqs-temp-humidity-all-meas",
  "aqs-temp-humidity-co2-pm25-tvoc-meas",
  "aqs-temp-humidity-tvoc-level-pm25-meas",
}

local function configure(driver, device)
  -- we have to read the unit before reports of values will do anything
  for _, cluster in ipairs(units_required) do
    device:send(cluster.attributes.MeasurementUnit:read(device))
  end

  -- check to see if device can switch to a more limited profile based on cluster support
  local temp_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureMeasurement.ID)
  local humidity_eps = embedded_cluster_utils.get_endpoints(device, clusters.RelativeHumidityMeasurement.ID)
  local co_level_eps = embedded_cluster_utils.get_endpoints(device, clusters.CarbonMonoxideConcentrationMeasurement.ID, {feature_bitmap = clusters.CarbonMonoxideConcentrationMeasurement.types.Feature.LEVEL_INDICATION})
  local co_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.CarbonMonoxideConcentrationMeasurement.ID, {feature_bitmap = clusters.CarbonMonoxideConcentrationMeasurement.types.Feature.NUMERIC_MEASUREMENT})
  local co2_level_eps = embedded_cluster_utils.get_endpoints(device, clusters.CarbonDioxideConcentrationMeasurement.ID, {feature_bitmap = clusters.CarbonDioxideConcentrationMeasurement.types.Feature.LEVEL_INDICATION})
  local co2_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.CarbonDioxideConcentrationMeasurement.ID, {feature_bitmap = clusters.CarbonDioxideConcentrationMeasurement.types.Feature.NUMERIC_MEASUREMENT})
  local no2_level_eps = embedded_cluster_utils.get_endpoints(device, clusters.NitrogenDioxideConcentrationMeasurement.ID, {feature_bitmap = clusters.NitrogenDioxideConcentrationMeasurement.types.Feature.LEVEL_INDICATION})
  local no2_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.NitrogenDioxideConcentrationMeasurement.ID, {feature_bitmap = clusters.NitrogenDioxideConcentrationMeasurement.types.Feature.NUMERIC_MEASUREMENT})
  local ozone_level_eps = embedded_cluster_utils.get_endpoints(device, clusters.OzoneConcentrationMeasurement.ID, {feature_bitmap = clusters.OzoneConcentrationMeasurement.types.Feature.LEVEL_INDICATION})
  local ozone_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.OzoneConcentrationMeasurement.ID, {feature_bitmap = clusters.OzoneConcentrationMeasurement.types.Feature.NUMERIC_MEASUREMENT})
  local formaldehyde_level_eps = embedded_cluster_utils.get_endpoints(device, clusters.FormaldehydeConcentrationMeasurement.ID, {feature_bitmap = clusters.FormaldehydeConcentrationMeasurement.types.Feature.LEVEL_INDICATION})
  local formaldehyde_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.FormaldehydeConcentrationMeasurement.ID, {feature_bitmap = clusters.FormaldehydeConcentrationMeasurement.types.Feature.NUMERIC_MEASUREMENT})
  local pm1_level_eps = embedded_cluster_utils.get_endpoints(device, clusters.Pm1ConcentrationMeasurement.ID, {feature_bitmap = clusters.Pm1ConcentrationMeasurement.types.Feature.LEVEL_INDICATION})
  local pm1_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.Pm1ConcentrationMeasurement.ID, {feature_bitmap = clusters.Pm1ConcentrationMeasurement.types.Feature.NUMERIC_MEASUREMENT})
  local pm2_5_level_eps = embedded_cluster_utils.get_endpoints(device, clusters.Pm25ConcentrationMeasurement.ID, {feature_bitmap = clusters.Pm25ConcentrationMeasurement.types.Feature.LEVEL_INDICATION})
  local pm2_5_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.Pm25ConcentrationMeasurement.ID, {feature_bitmap = clusters.Pm25ConcentrationMeasurement.types.Feature.NUMERIC_MEASUREMENT})
  local pm10_level_eps = embedded_cluster_utils.get_endpoints(device, clusters.Pm10ConcentrationMeasurement.ID, {feature_bitmap = clusters.Pm10ConcentrationMeasurement.types.Feature.LEVEL_INDICATION})
  local pm10_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.Pm10ConcentrationMeasurement.ID, {feature_bitmap = clusters.Pm10ConcentrationMeasurement.types.Feature.NUMERIC_MEASUREMENT})
  local radon_level_eps = embedded_cluster_utils.get_endpoints(device, clusters.RadonConcentrationMeasurement.ID, {feature_bitmap = clusters.RadonConcentrationMeasurement.types.Feature.LEVEL_INDICATION})
  local radon_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.RadonConcentrationMeasurement.ID, {feature_bitmap = clusters.RadonConcentrationMeasurement.types.Feature.NUMERIC_MEASUREMENT})
  local tvoc_level_eps = embedded_cluster_utils.get_endpoints(device, clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID, {feature_bitmap = clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.types.Feature.LEVEL_INDICATION})
  local tvoc_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID, {feature_bitmap = clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.types.Feature.NUMERIC_MEASUREMENT})

  local profile_name = "aqs"
  local level_indication_support = ""
  local numeric_measurement_support = ""

  if #temp_eps > 0 then
    profile_name = profile_name .. "-temp"
  end
  if #humidity_eps > 0 then
    profile_name = profile_name .. "-humidity"
  end
  if #co_level_eps > 0 then
    level_indication_support = level_indication_support .. "-co"
  end
  if #co2_level_eps > 0 then
    level_indication_support = level_indication_support .. "-co2"
  end
  if #no2_level_eps > 0 then
    level_indication_support = level_indication_support .. "-no2"
  end
  if #ozone_level_eps > 0 then
    level_indication_support = level_indication_support .. "-ozone"
  end
  if #formaldehyde_level_eps > 0 then
    level_indication_support = level_indication_support .. "-formaldehyde"
  end
  if #pm1_level_eps > 0 then
    level_indication_support = level_indication_support .. "-pm1"
  end
  if #pm2_5_level_eps > 0 then
    level_indication_support = level_indication_support .. "-pm25"
  end
  if #pm10_level_eps > 0 then
    level_indication_support = level_indication_support .. "-pm10"
  end
  if #radon_level_eps > 0 then
    level_indication_support = level_indication_support .. "-radon"
  end
  if #tvoc_level_eps > 0 then
    level_indication_support = level_indication_support .. "-tvoc"
  end
  -- If all endpoints are supported, use '-all' in the profile name so that it
  -- remains under the profile name character limit
  if level_indication_support == "-co-co2-no2-ozone-formaldehyde-pm1-pm25-pm10-radon-tvoc" then
    level_indication_support = "-all"
  end
  if level_indication_support ~= "" then
    profile_name = profile_name .. level_indication_support .. "-level"
  end

  if #co_meas_eps > 0 then
    numeric_measurement_support = numeric_measurement_support .. "-co"
  end
  if #co2_meas_eps > 0 then
    numeric_measurement_support = numeric_measurement_support .. "-co2"
  end
  if #no2_meas_eps > 0 then
    numeric_measurement_support = numeric_measurement_support .. "-no2"
  end
  if #ozone_meas_eps > 0 then
    numeric_measurement_support = numeric_measurement_support .. "-ozone"
  end
  if #formaldehyde_meas_eps > 0 then
    numeric_measurement_support = numeric_measurement_support .. "-formaldehyde"
  end
  if #pm1_meas_eps > 0 then
    numeric_measurement_support = numeric_measurement_support .. "-pm1"
  end
  if #pm2_5_meas_eps > 0 then
    numeric_measurement_support = numeric_measurement_support .. "-pm25"
  end
  if #pm10_meas_eps > 0 then
    numeric_measurement_support = numeric_measurement_support .. "-pm10"
  end
  if #radon_meas_eps > 0 then
    numeric_measurement_support = numeric_measurement_support .. "-radon"
  end
  if #tvoc_meas_eps > 0 then
    numeric_measurement_support = numeric_measurement_support .. "-tvoc"
  end
  -- If all endpoints are supported, use '-all' in the profile name so that it
  -- remains under the profile name character limit
  if numeric_measurement_support == "-co-co2-no2-ozone-formaldehyde-pm1-pm25-pm10-radon-tvoc" then
    numeric_measurement_support = "-all"
  end
  if numeric_measurement_support ~= "" then
    profile_name = profile_name .. numeric_measurement_support .. "-meas"
  end

  if not tbl_contains(supported_profiles, profile_name) then
    device.log.warn_with({hub_logs=true}, string.format("No matching profile for device. Tried to use profile %s", profile_name))
    if #co_meas_eps > 0 or #no2_meas_eps > 0 or #ozone_meas_eps > 0 or #formaldehyde_meas_eps > 0 or
        #pm1_meas_eps > 0 or #pm10_meas_eps > 0 or #radon_meas_eps > 0 then
      profile_name = "aqs-temp-humidity-all-meas"
    elseif #humidity_eps > 0 or #temp_eps > 0 or #co2_meas_eps > 0 or #pm2_5_meas_eps > 0 or #tvoc_meas_eps > 0 then
      profile_name = "aqs-temp-humidity-co2-pm25-tvoc-meas"
    else
      -- device only supports air quality at this point
      profile_name = "aqs"
    end
  end
  device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s", profile_name))
  device:try_update_metadata({profile = profile_name})
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
  [capabilities.tvocMeasurement.NAME] = units.PPM
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

local conversion_tables = {
  [units.PPM] = {
    [units.PPM] = function(value) return utils.round(value) end
  },
  [units.PPB] = {
    [units.PPM] = function(value) return utils.round(value/(10^3)) end
  },
  [units.PPT] = {
    [units.PPM] = function(value) return utils.round(value/(10^6)) end
  },
  [units.MGM3] = {
    [units.UGM3] = function(value) return utils.round(value * (10^3)) end
  },
  [units.UGM3] = {
    [units.UGM3] = function(value) return utils.round(value) end
  },
  [units.NGM3] = {
    [units.UGM3] = function(value) return utils.round(value/(10^3)) end
  },
  [units.BQM3] = {
    [units.PCIL] = function(value) return utils.round(value/37) end
  }
}

local function unit_conversion(value, from_unit, to_unit)
  local conversion_function = conversion_tables[from_unit][to_unit]
  if conversion_function == nil then
    return nil, string.format("Unsupported unit conversion from %s to %s", unit_strings[from_unit], unit_strings[to_unit])
  end

  if value == nil then
    return nil, "Unit conversion value is nil"
  end
  return conversion_function(value)
end

local function measurementHandlerFactory(capability_name, attribute, target_unit)
  return function(driver, device, ib, response)
    local reporting_unit = device:get_field(capability_name.."_unit")

    if reporting_unit == nil then
      reporting_unit = unit_default[capability_name]
      device:set_field(capability_name.."_unit", reporting_unit, {persist = true})
    end

    local value, err_msg
    if reporting_unit then
      value, err_msg = unit_conversion(ib.data.value, reporting_unit, target_unit)
    end

    if value then
      device:emit_event_for_endpoint(ib.endpoint_id, attribute({value = value, unit = unit_strings[target_unit]}))
      -- handle case where device profile supports both fineDustLevel and dustLevel
      if capability_name == capabilities.fineDustSensor.NAME and device:supports_capability(capabilities.dustSensor) then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.dustSensor.fineDustLevel({value = value, unit = unit_strings[target_unit]}))
      end
    else
      log.info_with({hub_logs = true}, err_msg)
    end
  end
end

local function levelHandlerFactory(attribute)
  return function(driver, device, ib, response)
    device:emit_event_for_endpoint(ib.endpoint_id, attribute(level_strings[ib.data.value]))
  end
end

-- Matter Handlers --
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

local function pressure_attr_handler(driver, device, ib, response)
  local pressure = utils.round(ib.data.value / 10.0)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.atmosphericPressureMeasurement.atmosphericPressure(pressure))
end

local matter_air_quality_sensor_handler = {
  NAME = "matter-air-quality-sensor",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = configure
  },
  matter_handlers = {
    attr = {
      [clusters.AirQuality.ID] = {
        [clusters.AirQuality.attributes.AirQuality.ID] = air_quality_attr_handler,
      },
      [clusters.PressureMeasurement.ID] = {
        [clusters.PressureMeasurement.attributes.MeasuredValue.ID] = pressure_attr_handler
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
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.tvocMeasurement.NAME, capabilities.tvocMeasurement.tvocLevel, units.PPM),
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.tvocMeasurement.NAME),
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue.ID] = levelHandlerFactory(capabilities.tvocHealthConcern.tvocHealthConcern)
      }
    }
  },
  subscribed_attributes = subscribed_attributes,
  can_handle = is_matter_air_quality_sensor
}

return matter_air_quality_sensor_handler
