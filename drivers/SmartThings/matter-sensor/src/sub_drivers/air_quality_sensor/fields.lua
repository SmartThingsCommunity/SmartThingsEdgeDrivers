-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local utils = require "st.utils"
local version = require "version"

-- Include driver-side definitions when lua libs api version is < 10
if version.api < 10 then
  clusters.AirQuality = require "embedded_clusters.AirQuality"
  clusters.CarbonMonoxideConcentrationMeasurement = require "embedded_clusters.CarbonMonoxideConcentrationMeasurement"
  clusters.CarbonDioxideConcentrationMeasurement = require "embedded_clusters.CarbonDioxideConcentrationMeasurement"
  clusters.FormaldehydeConcentrationMeasurement = require "embedded_clusters.FormaldehydeConcentrationMeasurement"
  clusters.NitrogenDioxideConcentrationMeasurement = require "embedded_clusters.NitrogenDioxideConcentrationMeasurement"
  clusters.OzoneConcentrationMeasurement = require "embedded_clusters.OzoneConcentrationMeasurement"
  clusters.Pm1ConcentrationMeasurement = require "embedded_clusters.Pm1ConcentrationMeasurement"
  clusters.Pm10ConcentrationMeasurement = require "embedded_clusters.Pm10ConcentrationMeasurement"
  clusters.Pm25ConcentrationMeasurement = require "embedded_clusters.Pm25ConcentrationMeasurement"
  clusters.RadonConcentrationMeasurement = require "embedded_clusters.RadonConcentrationMeasurement"
  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement = require "embedded_clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement"
end


local AirQualitySensorFields = {}

AirQualitySensorFields.AIR_QUALITY_SENSOR_DEVICE_TYPE_ID = 0x002C

AirQualitySensorFields.SUPPORTED_COMPONENT_CAPABILITIES = "__supported_component_capabilities"

AirQualitySensorFields.units_required = {
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

AirQualitySensorFields.supported_profiles =
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

AirQualitySensorFields.CONCENTRATION_MEASUREMENT_MAP = {
  [capabilities.carbonMonoxideMeasurement]    = {"-co",    clusters.CarbonMonoxideConcentrationMeasurement, "N/A"},
  [capabilities.carbonMonoxideHealthConcern]  = {"-co",    clusters.CarbonMonoxideConcentrationMeasurement, capabilities.carbonMonoxideHealthConcern.supportedCarbonMonoxideValues},
  [capabilities.carbonDioxideMeasurement]     = {"-co2",   clusters.CarbonDioxideConcentrationMeasurement, "N/A"},
  [capabilities.carbonDioxideHealthConcern]   = {"-co2",   clusters.CarbonDioxideConcentrationMeasurement, capabilities.carbonDioxideHealthConcern.supportedCarbonDioxideValues},
  [capabilities.nitrogenDioxideMeasurement]   = {"-no2",   clusters.NitrogenDioxideConcentrationMeasurement, "N/A"},
  [capabilities.nitrogenDioxideHealthConcern] = {"-no2",   clusters.NitrogenDioxideConcentrationMeasurement, capabilities.nitrogenDioxideHealthConcern.supportedNitrogenDioxideValues},
  [capabilities.ozoneMeasurement]             = {"-ozone", clusters.OzoneConcentrationMeasurement, "N/A"},
  [capabilities.ozoneHealthConcern]           = {"-ozone", clusters.OzoneConcentrationMeasurement, capabilities.ozoneHealthConcern.supportedOzoneValues},
  [capabilities.formaldehydeMeasurement]      = {"-ch2o",  clusters.FormaldehydeConcentrationMeasurement, "N/A"},
  [capabilities.formaldehydeHealthConcern]    = {"-ch2o",  clusters.FormaldehydeConcentrationMeasurement, capabilities.formaldehydeHealthConcern.supportedFormaldehydeValues},
  [capabilities.veryFineDustSensor]           = {"-pm1",   clusters.Pm1ConcentrationMeasurement, "N/A"},
  [capabilities.veryFineDustHealthConcern]    = {"-pm1",   clusters.Pm1ConcentrationMeasurement, capabilities.veryFineDustHealthConcern.supportedVeryFineDustValues},
  [capabilities.fineDustSensor]               = {"-pm25",  clusters.Pm25ConcentrationMeasurement, "N/A"},
  [capabilities.fineDustHealthConcern]        = {"-pm25",  clusters.Pm25ConcentrationMeasurement, capabilities.fineDustHealthConcern.supportedFineDustValues},
  [capabilities.dustSensor]                   = {"-pm10",  clusters.Pm10ConcentrationMeasurement, "N/A"},
  [capabilities.dustHealthConcern]            = {"-pm10",  clusters.Pm10ConcentrationMeasurement, capabilities.dustHealthConcern.supportedDustValues},
  [capabilities.radonMeasurement]             = {"-radon", clusters.RadonConcentrationMeasurement, "N/A"},
  [capabilities.radonHealthConcern]           = {"-radon", clusters.RadonConcentrationMeasurement, capabilities.radonHealthConcern.supportedRadonValues},
  [capabilities.tvocMeasurement]              = {"-tvoc",  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement, "N/A"},
  [capabilities.tvocHealthConcern]            = {"-tvoc",  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement, capabilities.tvocHealthConcern.supportedTvocValues},
}


AirQualitySensorFields.CONCENTRATION_MEASUREMENT_PROFILE_ORDERING = {
  capabilities.carbonMonoxideMeasurement,
  capabilities.carbonMonoxideHealthConcern,
  capabilities.carbonDioxideMeasurement,
  capabilities.carbonDioxideHealthConcern,
  capabilities.nitrogenDioxideMeasurement,
  capabilities.nitrogenDioxideHealthConcern,
  capabilities.ozoneMeasurement,
  capabilities.ozoneHealthConcern,
  capabilities.formaldehydeMeasurement,
  capabilities.formaldehydeHealthConcern,
  capabilities.veryFineDustSensor,
  capabilities.veryFineDustHealthConcern,
  capabilities.fineDustSensor,
  capabilities.fineDustHealthConcern,
  capabilities.dustSensor,
  capabilities.dustHealthConcern,
  capabilities.radonMeasurement,
  capabilities.radonHealthConcern,
  capabilities.tvocMeasurement,
  capabilities.tvocHealthConcern,
}

AirQualitySensorFields.units = {
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

local units = AirQualitySensorFields.units -- copy to remove the prefix in uses below 

AirQualitySensorFields.unit_strings = {
  [units.PPM] = "ppm",
  [units.PPB] = "ppb",
  [units.PPT] = "ppt",
  [units.MGM3] = "mg/m^3",
  [units.NGM3] = "ng/m^3",
  [units.UGM3] = "μg/m^3",
  [units.BQM3] = "Bq/m^3",
  [units.PCIL] = "pCi/L"
}

AirQualitySensorFields.unit_default = {
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
AirQualitySensorFields.level_strings = {
  [clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.UNKNOWN] = "unknown",
  [clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.LOW] = "good",
  [clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.MEDIUM] = "moderate",
  [clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.HIGH] = "unhealthy",
  [clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.CRITICAL] = "hazardous",
}

AirQualitySensorFields.conversion_tables = {
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

return AirQualitySensorFields
