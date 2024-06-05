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

local MatterDriver = require "st.matter.driver"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local utils = require "st.utils"

local log = require "log"
local AIR_QUALITY_SENSOR_DEVICE_TYPE_ID = 0x002C

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

local common_optional_clusters = {
  clusters.RelativeHumidityMeasurement.ID,
  clusters.CarbonDioxideConcentrationMeasurement.ID,
  clusters.Pm25ConcentrationMeasurement.ID,
  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID
}

-- TemperatureMeasurement and RelativeHumidityMeasurement are clusters included in 
-- Air Quality Sensor that are not included in this bitmap for legacy reasons.
local AIR_QUALITY_BIT_MAP = {
  [capabilities.airQualityHealthConcern.ID]       = {0, {clusters.AirQuality}},
  [capabilities.carbonDioxideMeasurement.ID]      = {1, {clusters.CarbonDioxideConcentrationMeasurement}},
  [capabilities.carbonDioxideHealthConcern.ID]    = {2, {clusters.CarbonDioxideConcentrationMeasurement}},
  [capabilities.carbonMonoxideMeasurement.ID]     = {3, {clusters.CarbonMonoxideConcentrationMeasurement}},
  [capabilities.carbonMonoxideHealthConcern.ID]   = {4, {clusters.CarbonMonoxideConcentrationMeasurement}},
  [capabilities.dustSensor.ID]                    = {5, {clusters.Pm10ConcentrationMeasurement, clusters.Pm25ConcentrationMeasurement}},
  [capabilities.dustHealthConcern.ID]             = {6, {clusters.Pm10ConcentrationMeasurement, clusters.Pm25ConcentrationMeasurement}},
  [capabilities.fineDustSensor.ID]                = {7, {clusters.Pm25ConcentrationMeasurement}},
  [capabilities.fineDustHealthConcern.ID]         = {8, {clusters.Pm25ConcentrationMeasurement}},
  [capabilities.formaldehydeMeasurement.ID]       = {9, {clusters.FormaldehydeConcentrationMeasurement}},
  [capabilities.formaldehydeHealthConcern.ID]     = {10, {clusters.FormaldehydeConcentrationMeasurement}},
  [capabilities.nitrogenDioxideHealthConcern.ID]  = {11, {clusters.NitrogenDioxideConcentrationMeasurement}},
  [capabilities.nitrogenDioxideMeasurement.ID]    = {12, {clusters.NitrogenDioxideConcentrationMeasurement}},
  [capabilities.ozoneHealthConcern.ID]            = {13, {clusters.OzoneConcentrationMeasurement}},
  [capabilities.ozoneMeasurement.ID]              = {14, {clusters.OzoneConcentrationMeasurement}},
  [capabilities.radonHealthConcern.ID]            = {15, {clusters.RadonConcentrationMeasurement}},
  [capabilities.radonMeasurement.ID]              = {16, {clusters.RadonConcentrationMeasurement}},
  [capabilities.tvocHealthConcern.ID]             = {17, {clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement}},
  [capabilities.tvocMeasurement.ID]               = {18, {clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement}},
  [capabilities.veryFineDustHealthConcern.ID]     = {19, {clusters.Pm1ConcentrationMeasurement}},
  [capabilities.veryFineDustSensor.ID]            = {20, {clusters.Pm1ConcentrationMeasurement}},
}

local function create_air_quality_hex_bitmap(device)
  local bitmap = 0
  for cap_id, map in pairs(AIR_QUALITY_BIT_MAP) do
    local has_necessary_attributes = true
    for _, cluster in ipairs(map[2]) do
      -- air quality is mandatory, so it will always be included
      if cluster.ID ~= clusters.AirQuality.ID then
        -- capability describes either a HealthConcern or Measurement/Sensor
        local attr_eps = 0
        if (cap_id:match("HealthConcern$")) then
          attr_eps = device:get_endpoints(cluster.ID, { feature_bitmap = cluster.types.Feature.LEVEL_INDICATION})
        elseif (cap_id:match("Measurement$") or cap_id:match("Sensor$")) then
          attr_eps = device:get_endpoints(cluster.ID, { feature_bitmap = cluster.types.Feature.NUMERIC_MEASUREMENT})
        end
        if attr_eps == 0 then
          has_necessary_attributes = false
          break
        end
      end
    end
    if has_necessary_attributes then
      bitmap = bitmap | (1 << map[1])
    end
  end
  local hex_bitmap = string.format("%x", bitmap)
  return hex_bitmap
end

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
  "air-quality-sensor",
  "air-quality-sensor-temp-humidity-all-level-all-meas",
  "air-quality-sensor-temp-humidity-all-level",
  "air-quality-sensor-temp-humidity-all-meas",
  "air-quality-sensor-temp-humidity-co2-pm25-tvoc-meas",
  "air-quality-sensor-temp-humidity-tvoc-level-pm25-meas",
}

local function configure(driver, device)
  -- we have to read the unit before reports of values will do anything
  for _, cluster in ipairs(units_required) do
    device:send(cluster.attributes.MeasurementUnit:read(device))
  end

  local temp_eps = device:get_endpoints(clusters.TemperatureMeasurement.ID)
  local humidity_eps = device:get_endpoints(clusters.RelativeHumidityMeasurement.ID)

  local profile_name = "air-quality-sensor"

  local hex_aq_bitmap = create_air_quality_hex_bitmap(device)
  profile_name = "air-quality-sensor-" .. hex_aq_bitmap

  if #temp_eps > 0 then
    profile_name = profile_name .. "-temp"
  end
  if #humidity_eps > 0 then
    profile_name = profile_name .. "-humidity"
  end

  -- can only be accessed if the built profile name does not exist in or
  -- supported_profiles table
  if not tbl_contains(supported_profiles, profile_name) then
    log.warn_with({hub_logs=true}, string.format("No matching profile for device. Tried to use profile %s", profile_name))
    profile_name = ""

    local best_fit_profile_found = false

    -- checks if device supports a cluster only supported in the catch-all
    -- bits are for measurements of no2, co, radon, formaldehyde, ozone, 
    -- pm1, or pm10
    local check_bits = {3, 12, 14, 9, 20, 5, 16}
    for bit in check_bits do
      if (hex_aq_bitmap >> bit) & 1 == 1 then
        best_fit_profile_found = true
        profile_name = "air-quality-sensor-15522b-temp-humidity"
        break
      end
    end
    -- this is currently our next-smallest choice of profile
    if not best_fit_profile_found then
      profile_name = "air-quality-sensor-40023-temp-humidity"
    end
  end
  log.info_with({hub_logs=true}, string.format("Updating device profile to %s", profile_name))
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
    log.info_with( {hub_logs = true} , string.format("Unsupported unit conversionfrom %s to %s", unit_strings[from_unit], unit_strings[to_unit]))
    return 1
  end

  if value == nil then
    log.info_with( {hub_logs = true} , "unit conversion value is nil")
    return 1
  end
  return conversion_function(value)
end

local function measurementHandlerFactory(capability_name, attribute, target_unit)
  return function(driver, device, ib, response)
    local reporting_unit = device:get_field(capability_name.."_unit")

    -- if reporting_unit is nil, initial value is not updated.
    if reporting_unit == nil then
      reporting_unit = unit_default[capability_name]
      device:set_field(capability_name.."_unit", reporting_unit, {persist = true})
    end

    if reporting_unit then
      local value = unit_conversion(ib.data.value, reporting_unit, target_unit)
      device:emit_event_for_endpoint(ib.endpoint_id, attribute({value = value, unit = unit_strings[target_unit]}))
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
    added = device_added,
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
        [clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.dustSensor.NAME, capabilities.dustSensor.fineDustLevel, units.UGM3),
        [clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.dustSensor.NAME),
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
