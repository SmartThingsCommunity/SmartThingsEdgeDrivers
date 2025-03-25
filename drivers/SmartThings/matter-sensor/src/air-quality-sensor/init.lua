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
  "aqs-temp-humidity-co2-pm1-pm25-pm10-meas",
  "aqs-temp-humidity-tvoc-level-pm25-meas",
  "aqs-temp-humidity-tvoc-meas",
}

local AIR_QUALITY_MAP = {
  {capabilities.carbonMonoxideMeasurement.ID,    "-co",    clusters.CarbonMonoxideConcentrationMeasurement},
  {capabilities.carbonMonoxideHealthConcern.ID,  "-co",    clusters.CarbonMonoxideConcentrationMeasurement},
  {capabilities.carbonDioxideMeasurement.ID,     "-co2",   clusters.CarbonDioxideConcentrationMeasurement},
  {capabilities.carbonDioxideHealthConcern.ID,   "-co2",   clusters.CarbonDioxideConcentrationMeasurement},
  {capabilities.nitrogenDioxideHealthConcern.ID, "-no2",   clusters.NitrogenDioxideConcentrationMeasurement},
  {capabilities.nitrogenDioxideMeasurement.ID,   "-no2",   clusters.NitrogenDioxideConcentrationMeasurement},
  {capabilities.ozoneHealthConcern.ID,           "-ozone", clusters.OzoneConcentrationMeasurement},
  {capabilities.ozoneMeasurement.ID,             "-ozone", clusters.OzoneConcentrationMeasurement},
  {capabilities.formaldehydeMeasurement.ID,      "-ch2o",  clusters.FormaldehydeConcentrationMeasurement},
  {capabilities.formaldehydeHealthConcern.ID,    "-ch2o",  clusters.FormaldehydeConcentrationMeasurement},
  {capabilities.veryFineDustHealthConcern.ID,    "-pm1",   clusters.Pm1ConcentrationMeasurement},
  {capabilities.veryFineDustSensor.ID,           "-pm1",   clusters.Pm1ConcentrationMeasurement},
  {capabilities.fineDustSensor.ID,               "-pm25",  clusters.Pm25ConcentrationMeasurement},
  {capabilities.fineDustHealthConcern.ID,        "-pm25",  clusters.Pm25ConcentrationMeasurement},
  {capabilities.dustSensor.ID,                   "-pm10",  clusters.Pm10ConcentrationMeasurement},
  {capabilities.dustHealthConcern.ID,            "-pm10",  clusters.Pm10ConcentrationMeasurement},
  {capabilities.radonHealthConcern.ID,           "-radon", clusters.RadonConcentrationMeasurement},
  {capabilities.radonMeasurement.ID,             "-radon", clusters.RadonConcentrationMeasurement},
  {capabilities.tvocHealthConcern.ID,            "-tvoc",  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement},
  {capabilities.tvocMeasurement.ID,              "-tvoc",  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement},
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

local function do_configure(driver, device)
  local temp_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureMeasurement.ID)
  local humidity_eps = embedded_cluster_utils.get_endpoints(device, clusters.RelativeHumidityMeasurement.ID)

  -- we have to read the unit before reports of values will do anything
  for _, cluster in ipairs(units_required) do
    device:send(cluster.attributes.MeasurementUnit:read(device))
  end

  local profile_name = "aqs"

  if #temp_eps > 0 then
    profile_name = profile_name .. "-temp"
  end
  if #humidity_eps > 0 then
    profile_name = profile_name .. "-humidity"
  end

  local meas_name, level_name = create_level_measurement_profile(device)

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

  if not tbl_contains(supported_profiles, profile_name) then
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

-- All ConcentrationMeasurement clusters inherit from the same base cluster definitions,
-- so CarbonMonoxideConcentrationMeasurement is used below but the same enum types exist
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
    [units.PPM] = function(value) return utils.round(value) end,
    [units.PPB] = function(value) return utils.round(value * (10^3)) end
  },
  [units.PPB] = {
    [units.PPM] = function(value) return utils.round(value/(10^3)) end,
    [units.PPB] = function(value) return utils.round(value) end
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
    log.info_with( {hub_logs = true} , string.format("Unsupported unit conversion from %s to %s", unit_strings[from_unit], unit_strings[to_unit]))
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

    if reporting_unit == nil then
      reporting_unit = unit_default[capability_name]
      device:set_field(capability_name.."_unit", reporting_unit, {persist = true})
    end

    if reporting_unit then
      local value = unit_conversion(ib.data.value, reporting_unit, target_unit)
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
    doConfigure = do_configure
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
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.tvocMeasurement.NAME, capabilities.tvocMeasurement.tvocLevel, units.PPB),
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.tvocMeasurement.NAME),
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue.ID] = levelHandlerFactory(capabilities.tvocHealthConcern.tvocHealthConcern)
      }
    }
  },
  subscribed_attributes = subscribed_attributes,
  can_handle = is_matter_air_quality_sensor
}

return matter_air_quality_sensor_handler
