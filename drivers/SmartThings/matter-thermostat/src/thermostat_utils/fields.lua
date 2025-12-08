-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local version = require "version"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local st_utils = require "st.utils"

if version.api < 10 then
  clusters.CarbonDioxideConcentrationMeasurement = require "embedded_clusters.CarbonDioxideConcentrationMeasurement"
  clusters.CarbonMonoxideConcentrationMeasurement = require "embedded_clusters.CarbonMonoxideConcentrationMeasurement"
  clusters.Pm10ConcentrationMeasurement = require "embedded_clusters.Pm10ConcentrationMeasurement"
  clusters.Pm25ConcentrationMeasurement = require "embedded_clusters.Pm25ConcentrationMeasurement"
  clusters.FormaldehydeConcentrationMeasurement = require "embedded_clusters.FormaldehydeConcentrationMeasurement"
  clusters.NitrogenDioxideConcentrationMeasurement = require "embedded_clusters.NitrogenDioxideConcentrationMeasurement"
  clusters.OzoneConcentrationMeasurement = require "embedded_clusters.OzoneConcentrationMeasurement"
  clusters.RadonConcentrationMeasurement = require "embedded_clusters.RadonConcentrationMeasurement"
  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement = require "embedded_clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement"
  clusters.Pm1ConcentrationMeasurement = require "embedded_clusters.Pm1ConcentrationMeasurement"
  clusters.Thermostat.types.ThermostatSystemMode.DRY = 0x8  -- ThermostatSystemMode added in Matter 1.2
  clusters.Thermostat.types.ThermostatSystemMode.SLEEP = 0x9 -- ThermostatSystemMode added in Matter 1.2
end

local ThermostatFields = {}

ThermostatFields.SUPPORTED_COMPONENT_CAPABILITIES = "__supported_component_capabilities"

ThermostatFields.SAVED_SYSTEM_MODE_IB = "__saved_system_mode_ib"
ThermostatFields.DISALLOWED_THERMOSTAT_MODES = "__DISALLOWED_CONTROL_OPERATIONS"
ThermostatFields.OPTIONAL_THERMOSTAT_MODES_SEEN = "__OPTIONAL_THERMOSTAT_MODES_SEEN"

ThermostatFields.RAC_DEVICE_TYPE_ID = 0x0072
ThermostatFields.AP_DEVICE_TYPE_ID = 0x002D
ThermostatFields.FAN_DEVICE_TYPE_ID = 0x002B
ThermostatFields.WATER_HEATER_DEVICE_TYPE_ID = 0x050F
ThermostatFields.HEAT_PUMP_DEVICE_TYPE_ID = 0x0309
ThermostatFields.THERMOSTAT_DEVICE_TYPE_ID = 0x0301
ThermostatFields.ELECTRICAL_SENSOR_DEVICE_TYPE_ID = 0x0510

ThermostatFields.MIN_ALLOWED_PERCENT_VALUE = 0
ThermostatFields.MAX_ALLOWED_PERCENT_VALUE = 100
ThermostatFields.CUMULATIVE_REPORTS_NOT_SUPPORTED = "__cumulative_reports_not_supported"
ThermostatFields.LAST_IMPORTED_REPORT_TIMESTAMP = "__last_imported_report_timestamp"
ThermostatFields.MINIMUM_ST_ENERGY_REPORT_INTERVAL = (15 * 60) -- 15 minutes, reported in seconds
ThermostatFields.TOTAL_CUMULATIVE_ENERGY_IMPORTED_MAP = "__total_cumulative_energy_imported_map"
ThermostatFields.SUPPORTED_WATER_HEATER_MODES_WITH_IDX = "__supported_water_heater_modes_with_idx"
ThermostatFields.COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
ThermostatFields.MGM3_PPM_CONVERSION_FACTOR = 24.45

--  For RPC version < 6:
--      issue context: driver cannot know a setpoint capability's unit (whether Celsius or Farenheit)
--          when a command is received, as the received arguments do not contain the unit.
--      workaround: map the following temperature ranges to either Celsius or Farenheit:
--          For Thermostats:
--              1. if the received setpoint command value is in the range 5 ~ 40, it is inferred as *C
--              2. if the received setpoint command value is in the range 41 ~ 104, it is inferred as *F
--          For Water Heaters:
--              1. if the received setpoint command value is in the range 30 ~ 80, it is inferred as *C
--              2. if the received setpoint command value is in the range 86 ~ 176, it is inferred as *F
--  For RPC version >= 6:
--      temperatureSetpoint always reports in Celsius, removing the need for the above workaround.
--      In this case, we use these fields simply to limit the setpoint's range to "reasonable" values on the platform.
ThermostatFields.THERMOSTAT_MAX_TEMP_IN_C = version.rpc >= 6 and 100.0 or 40.0
ThermostatFields.THERMOSTAT_MIN_TEMP_IN_C = version.rpc >= 6 and 0.0 or 5.0
ThermostatFields.WATER_HEATER_MAX_TEMP_IN_C = version.rpc >= 6 and 100.0 or 80.0
ThermostatFields.WATER_HEATER_MIN_TEMP_IN_C = version.rpc >= 6 and 0.0 or 30.0

ThermostatFields.setpoint_limit_device_field = {
  MIN_SETPOINT_DEADBAND_CHECKED = "MIN_SETPOINT_DEADBAND_CHECKED",
  MIN_HEAT = "MIN_HEAT",
  MAX_HEAT = "MAX_HEAT",
  MIN_COOL = "MIN_COOL",
  MAX_COOL = "MAX_COOL",
  MIN_DEADBAND = "MIN_DEADBAND",
  MIN_TEMP = "MIN_TEMP",
  MAX_TEMP = "MAX_TEMP"
}

ThermostatFields.battery_support = {
  NO_BATTERY = "NO_BATTERY",
  BATTERY_LEVEL = "BATTERY_LEVEL",
  BATTERY_PERCENTAGE = "BATTERY_PERCENTAGE"
}

ThermostatFields.profiling_data = {
  BATTERY_SUPPORT = "__BATTERY_SUPPORT",
  THERMOSTAT_RUNNING_STATE_SUPPORT = "__THERMOSTAT_RUNNING_STATE_SUPPORT"
}

ThermostatFields.THERMOSTAT_MODE_MAP = {
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

ThermostatFields.THERMOSTAT_OPERATING_MODE_MAP = {
  [0] = capabilities.thermostatOperatingState.thermostatOperatingState.heating,
  [1] = capabilities.thermostatOperatingState.thermostatOperatingState.cooling,
  [2] = capabilities.thermostatOperatingState.thermostatOperatingState.fan_only,
  [3] = capabilities.thermostatOperatingState.thermostatOperatingState.heating,
  [4] = capabilities.thermostatOperatingState.thermostatOperatingState.cooling,
  [5] = capabilities.thermostatOperatingState.thermostatOperatingState.fan_only,
  [6] = capabilities.thermostatOperatingState.thermostatOperatingState.fan_only,
}

ThermostatFields.WIND_MODE_MAP = {
  [0] = capabilities.windMode.windMode.sleepWind,
  [1] = capabilities.windMode.windMode.naturalWind
}

ThermostatFields.ROCK_MODE_MAP = {
  [0] = capabilities.fanOscillationMode.fanOscillationMode.horizontal,
  [1] = capabilities.fanOscillationMode.fanOscillationMode.vertical,
  [2] = capabilities.fanOscillationMode.fanOscillationMode.swing
}

ThermostatFields.AIR_QUALITY_MAP = {
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

ThermostatFields.units = {
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

local units = ThermostatFields.units -- copy units to avoid references below

ThermostatFields.unit_strings = {
  [units.PPM] = "ppm",
  [units.PPB] = "ppb",
  [units.PPT] = "ppt",
  [units.MGM3] = "mg/m^3",
  [units.NGM3] = "ng/m^3",
  [units.UGM3] = "μg/m^3",
  [units.BQM3] = "Bq/m^3",
  [units.PCIL] = "pCi/L"
}

ThermostatFields.unit_default = {
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
ThermostatFields.level_strings = {
  [clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.UNKNOWN] = "unknown",
  [clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.LOW] = "good",
  [clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.MEDIUM] = "moderate",
  [clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.HIGH] = "unhealthy",
  [clusters.CarbonMonoxideConcentrationMeasurement.types.LevelValueEnum.CRITICAL] = "hazardous",
}

-- measured in g/mol
ThermostatFields.molecular_weights = {
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

ThermostatFields.conversion_tables = {
  [units.PPM] = {
    [units.PPM] = function(value) return st_utils.round(value) end,
    [units.PPB] = function(value) return st_utils.round(value * (10^3)) end,
    [units.UGM3] = function(value, molecular_weight) return st_utils.round((value * molecular_weight * 10^3) / ThermostatFields.MGM3_PPM_CONVERSION_FACTOR) end,
    [units.MGM3] = function(value, molecular_weight) return st_utils.round((value * molecular_weight) / ThermostatFields.MGM3_PPM_CONVERSION_FACTOR) end,
  },
  [units.PPB] = {
    [units.PPM] = function(value) return st_utils.round(value/(10^3)) end,
    [units.PPB] = function(value) return st_utils.round(value) end,
  },
  [units.PPT] = {
    [units.PPM] = function(value) return st_utils.round(value/(10^6)) end
  },
  [units.MGM3] = {
    [units.UGM3] = function(value) return st_utils.round(value * (10^3)) end,
    [units.PPM] = function(value, molecular_weight) return st_utils.round((value * ThermostatFields.MGM3_PPM_CONVERSION_FACTOR) / molecular_weight) end,
  },
  [units.UGM3] = {
    [units.UGM3] = function(value) return st_utils.round(value) end,
    [units.PPM] = function(value, molecular_weight) return st_utils.round((value * ThermostatFields.MGM3_PPM_CONVERSION_FACTOR) / (molecular_weight * 10^3)) end,
  },
  [units.NGM3] = {
    [units.UGM3] = function(value) return st_utils.round(value/(10^3)) end
  },
  [units.BQM3] = {
    [units.PCIL] = function(value) return st_utils.round(value/37) end
  },
}

return ThermostatFields