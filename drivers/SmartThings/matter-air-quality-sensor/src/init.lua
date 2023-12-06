-- Copyright 2023 SmartThings
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

local airQualityID = "spacewonder52282.airQuality"
local nitrogenDioxideMeasurementID = "spacewonder52282.nitrogenDioxideMeasurement"
local ozoneMeasurementID = "spacewonder52282.ozoneMeasurement"
local airQuality = capabilities[airQualityID]
local nitrogenDioxideMeasurement = capabilities[nitrogenDioxideMeasurementID]
local ozoneMeasurement = capabilities[ozoneMeasurementID]

local subscribed_attributes = {
  [airQualityID] = {
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
  [capabilities.carbonDioxideMeasurement.ID] = {
    clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue,
    clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [nitrogenDioxideMeasurementID] = {
    clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasuredValue,
    clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasurementUnit
  },
  [ozoneMeasurementID] = {
    clusters.OzoneConcentrationMeasurement.attributes.MeasuredValue,
    clusters.OzoneConcentrationMeasurement.attributes.MeasurementUnit
  },
  [capabilities.formaldehydeMeasurement.ID] = {
    clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue,
    clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.veryFineDustSensor.ID] = {
    clusters.Pm1ConcentrationMeasurement.attributes.MeasuredValue,
    clusters.Pm1ConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.fineDustSensor.ID] = {
    clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue,
    clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.dustSensor.ID] = {
    clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue,
    clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.radonMeasurement.ID] = {
    clusters.RadonConcentrationMeasurement.attributes.MeasuredValue,
    clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit,
  },
  [capabilities.tvocMeasurement.ID] = {
    clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue,
    clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit,
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

local function configure(driver, device)
  -- we have to read the unit before reports of values will do anything
  for _, cluster in ipairs(units_required) do
    device:send(cluster.attributes.MeasurementUnit:read(device))
  end
end

local function device_added(driver, device)
  device:send(clusters.TemperatureMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.AirQuality.attributes.MeasuredValue:read(device))
  -- we _should_ have a unit by now
  for _, cluster in ipairs(units_required) do
    device:send(cluster.attributes.MeasuredValue:read(device))
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
  return conversion_function(value)
end

local function measurementHandlerFactory(capability_name, attribute, target_unit)
  return function(driver, device, ib, response)
    local reporting_unit = device:get_field(capability_name.."_unit")
    if reporting_unit then
      local value = unit_conversion(ib.data.value, reporting_unit, target_unit)
      device:emit_event_for_endpoint(ib.endpoint_id, attribute({value = value, unit = unit_strings[target_unit]}))
    end
  end
end

-- Matter Handlers --
local function air_quality_attr_handler(driver, device, ib, response)
  local state = ib.data.value
  if state == 0 then -- Unknown
    device:emit_event_for_endpoint(ib.endpoint_id, airQuality.airQuality.unknown())
  elseif state == 1 then -- Good
    device:emit_event_for_endpoint(ib.endpoint_id, airQuality.airQuality.good())
  elseif state == 2 then -- Fair
    device:emit_event_for_endpoint(ib.endpoint_id, airQuality.airQuality.fair())
  elseif state == 3 then -- Moderate
    device:emit_event_for_endpoint(ib.endpoint_id, airQuality.airQuality.moderate())
  elseif state == 4 then -- Poor
    device:emit_event_for_endpoint(ib.endpoint_id, airQuality.airQuality.poor())
  elseif state == 5 then -- VeryPoor
    device:emit_event_for_endpoint(ib.endpoint_id, airQuality.airQuality.veryPoor())
  elseif state == 6 then -- ExtremelyPoor
    device:emit_event_for_endpoint(ib.endpoint_id, airQuality.airQuality.extremelvPoor())
  end
end

local function temp_event_handler(driver, device, ib, response)
  local temp = ib.data.value / 100.0
  local unit = "C"
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperature({value = temp, unit = unit}))
end

local function humidity_attr_handler(driver, device, ib, response)
  local humidity = utils.round(ib.data.value / 100.0)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(humidity))
end

local matter_driver_template = {
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
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler,
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = humidity_attr_handler
      },
      [clusters.CarbonMonoxideConcentrationMeasurement.ID] = {
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.carbonMonoxideMeasurement.NAME, capabilities.carbonMonoxideMeasurement.carbonMonoxideLevel, units.PPM),
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.carbonMonoxideMeasurement.NAME)
      },
      [clusters.CarbonDioxideConcentrationMeasurement.ID] = {
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.carbonDioxideMeasurement.NAME, capabilities.carbonDioxideMeasurement.carbonDioxide, units.PPM),
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.carbonDioxideMeasurement.NAME)
      },
      [clusters.NitrogenDioxideConcentrationMeasurement.ID] = {
        [clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(nitrogenDioxideMeasurementID, nitrogenDioxideMeasurement.nitrogenDioxideLevel, units.PPM),
        [clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(nitrogenDioxideMeasurementID)
      },
      [clusters.OzoneConcentrationMeasurement.ID] = {
        [clusters.OzoneConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(ozoneMeasurementID, ozoneMeasurement.ozoneLevel, units.PPM),
        [clusters.OzoneConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(ozoneMeasurementID)
      },
      [clusters.FormaldehydeConcentrationMeasurement.ID] = {
        [clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.formaldehydeMeasurement.NAME, capabilities.formaldehydeMeasurement.formaldehydeLevel, units.PPM),
        [clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.formaldehydeMeasurement.NAME)
      },
      [clusters.Pm1ConcentrationMeasurement.ID] = {
        [clusters.Pm1ConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.veryFineDustSensor.NAME, capabilities.veryFineDustSensor.veryFineDustLevel, units.UGM3),
        [clusters.Pm1ConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.veryFineDustSensor.NAME)
      },
      [clusters.Pm25ConcentrationMeasurement.ID] = {
        [clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.fineDustSensor.NAME, capabilities.fineDustSensor.fineDustLevel, units.UGM3),
        [clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.fineDustSensor.NAME)
      },
      [clusters.Pm10ConcentrationMeasurement.ID] = {
        [clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.dustSensor.NAME, capabilities.dustSensor.dustLevel, units.UGM3),
        [clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.dustSensor.NAME)
      },
      [clusters.RadonConcentrationMeasurement.ID] = {
        [clusters.RadonConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.radonMeasurement.NAME, capabilities.radonMeasurement.radonLevel, units.PCIL),
        [clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.radonMeasurement.NAME)
      },
      [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID] = {
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue.ID] = measurementHandlerFactory(capabilities.tvocMeasurement.NAME, capabilities.tvocMeasurement.tvocLevel, units.PPM),
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit.ID] = store_unit_factory(capabilities.tvocMeasurement.NAME)
      }
    }
  },
  subscribed_attributes = subscribed_attributes,
}

local matter_driver = MatterDriver("matter-air-quality-sensor", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
