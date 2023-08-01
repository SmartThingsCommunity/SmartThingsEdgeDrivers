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

local log = require "log"
local utils = require "st.utils"

local CARBON_MONOXIDE_MEASUREMENT_UNIT = "CarbonMonoxideConcentrationMeasurement.MeasurementUnit"
local CARBON_DIOXIDE_MEASUREMENT_UNIT = "CarbonDioxideConcentrationMeasurement.MeasurementUnit"
local FORMALDEHYDE_MEASUREMENT_UNIT = "FormaldehydeConcentrationMeasurement.MeasurementUnit"
local PM1_MEASUREMENT_UNIT = "Pm1ConcentrationMeasurement.MeasurementUnit"
local PM25_MEASUREMENT_UNIT = "Pm25ConcentrationMeasurement.MeasurementUnit"
local PM10_MEASUREMENT_UNIT = "Pm10ConcentrationMeasurement.MeasurementUnit"
local RADON_MEASUREMENT_UNIT = "RadonConcentrationMeasurement.MeasurementUnit"
local TVOC_MEASUREMENT_UNIT = "TotalVolatileOrganicCompoundsConcentrationMeasurement.MeasurementUnit"

local function device_init(driver, device)
  device:subscribe()
end

local function device_added(driver, device)
  device:send(clusters.TemperatureMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredUnit:read(device))
  device:send(clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredUnit:read(device))
  device:send(clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredUnit:read(device))
  device:send(clusters.Pm1ConcentrationMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.Pm1ConcentrationMeasurement.attributes.MeasuredUnit:read(device))
  device:send(clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.Pm25ConcentrationMeasurement.attributes.MeasuredUnit:read(device))
  device:send(clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.Pm10ConcentrationMeasurement.attributes.MeasuredUnit:read(device))
  device:send(clusters.RadonConcentrationMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.RadonConcentrationMeasurement.attributes.MeasuredUnit:read(device))
  device:send(clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredUnit:read(device))
end

-- Matter Handlers --
local function temp_event_handler(attribute)
  return function(driver, device, ib, response)
    local temp = ib.data.value / 100.0
    local unit = "C"
    device:emit_event_for_endpoint(ib.endpoint_id, attribute({value = temp, unit = unit}))
  end
end

local function humidity_attr_handler(driver, device, ib, response)
  local humidity = math.floor(ib.data.value / 100.0)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(humidity))
end

local function carbon_monoxide_attr_handler(driver, device, ib, response)
  local value = ib.data.value
  local unit = device:get_field(CARBON_MONOXIDE_MEASUREMENT_UNIT)
  if unit == clusters.clusters.types.MeasurementUnitEnum.PPB then
    value = value / 1000
  elseif unit == clusters.clusters.types.MeasurementUnitEnum.PPT then
    value = value / 1000000
  end
  value = math.floor(value)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.carbonMonoxideMeasurement.carbonMonoxideLevel({value = value, unit = "ppm"}))
end

local function carbon_monoxide_unit_attr_handler(driver, device, ib, response)
  local unit = ib.data.value
  device:set_field(CARBON_MONOXIDE_MEASUREMENT_UNIT, unit, { persist = true })
end

local function carbon_dioxide_attr_handler(driver, device, ib, response)
  local value = ib.data.value
  local unit = device:get_field(CARBON_DIOXIDE_MEASUREMENT_UNIT)
  if unit == clusters.clusters.types.MeasurementUnitEnum.PPB then
    value = value / 1000
  elseif unit == clusters.clusters.types.MeasurementUnitEnum.PPT then
    value = value / 1000000
  end
  value = math.floor(value)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.carbonDioxideMeasurement.carbonDioxide({value = value}))
end

local function carbon_dioxide_unit_attr_handler(driver, device, ib, response)
  local unit = ib.data.value
  device:set_field(CARBON_DIOXIDE_MEASUREMENT_UNIT, unit, { persist = true })
end

local function formaldehyde_attr_handler(driver, device, ib, response)
  local value = ib.data.value
  local unit = device:get_field(FORMALDEHYDE_MEASUREMENT_UNIT)
  if unit == clusters.clusters.types.MeasurementUnitEnum.PPB then
    value = value / 1000
  elseif unit == clusters.clusters.types.MeasurementUnitEnum.PPT then
    value = value / 1000000
  end
  value = math.floor(value)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.formaldehydeMeasurement.formaldehydeLevel({value = value, unit = "ppm"}))
end

local function formaldehyde_unit_attr_handler(driver, device, ib, response)
  local unit = ib.data.value
  device:set_field(FORMALDEHYDE_MEASUREMENT_UNIT, unit, { persist = true })
end

local function pm1_attr_handler(driver, device, ib, response)
  local value = ib.data.value
  local unit = device:get_field(PM1_MEASUREMENT_UNIT)
  if unit == clusters.clusters.types.MeasurementUnitEnum.MGM3 then
    value = value * 1000
  elseif unit == clusters.clusters.types.MeasurementUnitEnum.NGM3 then
    value = value / 1000
  end
  value = math.floor(value)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.veryFineDustSensor.veryFineDustLevel({value = value}))
end

local function pm1_unit_attr_handler(driver, device, ib, response)
  local unit = ib.data.value
  device:set_field(PM1_MEASUREMENT_UNIT, unit, { persist = true })
end

local function pm25_attr_handler(driver, device, ib, response)
  local value = ib.data.value
  local unit = device:get_field(PM25_MEASUREMENT_UNIT)
  if unit == clusters.clusters.types.MeasurementUnitEnum.UGM3 then
    value = value / 1000
  elseif unit == clusters.clusters.types.MeasurementUnitEnum.NGM3 then
    value = value / 1000000
  end
  value = math.floor(value)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fineDustSensor.fineDustLevel({value = value}))
end

local function pm25_unit_attr_handler(driver, device, ib, response)
  local unit = ib.data.value
  device:set_field(PM25_MEASUREMENT_UNIT, unit, { persist = true })
end

local function pm10_attr_handler(driver, device, ib, response)
  local value = ib.data.value
  local unit = device:get_field(PM10_MEASUREMENT_UNIT)
  if unit == clusters.clusters.types.MeasurementUnitEnum.UGM3 then
    value = value / 1000
  elseif unit == clusters.clusters.types.MeasurementUnitEnum.NGM3 then
    value = value / 1000000
  end
  value = math.floor(value)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.dustSensor.dustLevel({value = value}))
end

local function pm10_unit_attr_handler(driver, device, ib, response)
  local unit = ib.data.value
  device:set_field(PM10_MEASUREMENT_UNIT, unit, { persist = true })
end

local function radon_attr_handler(driver, device, ib, response)
  local value = math.floor(ib.data.value / 37) -- BQM3 to pCi/L
  local unit = device:get_field(RADON_MEASUREMENT_UNIT)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.radonMeasurement.radonLevel({value = value, unit = "pCi/L"}))
end

local function radon_unit_attr_handler(driver, device, ib, response)
  local unit = ib.data.value
  device:set_field(RADON_MEASUREMENT_UNIT, unit, { persist = true })
end

local function tvoc_attr_handler(driver, device, ib, response)
  local value = ib.data.value
  local unit = device:get_field(TVOC_MEASUREMENT_UNIT)
  if unit == clusters.clusters.types.MeasurementUnitEnum.PPB then
    value = value / 1000
  elseif unit == clusters.clusters.types.MeasurementUnitEnum.PPT then
    value = value / 1000000
  end
  value = math.floor(value)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.formaldehydeMeasurement.formaldehydeLevel({value = value, unit = "ppm"}))
end

local function tvoc_unit_attr_handler(driver, device, ib, response)
  local unit = ib.data.value
  device:set_field(TVOC_MEASUREMENT_UNIT, unit, { persist = true })
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
  },
  matter_handlers = {
    attr = {
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler(capabilities.temperatureMeasurement.temperature),
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = humidity_attr_handler
      },
      [clusters.CarbonMonoxideConcentrationMeasurement.ID] = {
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue.ID] = carbon_monoxide_attr_handler
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = carbon_monoxide_unit_attr_handler
      },
      [clusters.CarbonDioxideConcentrationMeasurement.ID] = {
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue.ID] = carbon_dioxide_attr_handler
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = carbon_dioxide_unit_attr_handler
      },
      [clusters.FormaldehydeConcentrationMeasurement.ID] = {
        [clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue.ID] = formaldehyde_attr_handler
        [clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit.ID] = formaldehyde_unit_attr_handler
      },
      [clusters.Pm1ConcentrationMeasurement.ID] = {
        [clusters.Pm1ConcentrationMeasurement.attributes.MeasuredValue.ID] = pm1_attr_handler
        [clusters.Pm1ConcentrationMeasurement.attributes.MeasurementUnit.ID] = pm1_unit_attr_handler
      },
      [clusters.Pm25ConcentrationMeasurement.ID] = {
        [clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue.ID] = pm25_attr_handler
        [clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit.ID] = pm25_unit_attr_handler
      },
      [clusters.Pm10ConcentrationMeasurement.ID] = {
        [clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue.ID] = pm10_attr_handler
        [clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit.ID] = pm10_unit_attr_handler
      },
      [clusters.RadonConcentrationMeasurement.ID] = {
        [clusters.RadonConcentrationMeasurement.attributes.MeasuredValue.ID] = radon_attr_handler
        [clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit.ID] = radon_unit_attr_handler
      },
      [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID] = {
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue.ID] = tvoc_attr_handler
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit.ID] = tvoc_unit_attr_handler
      }
    }
  },
  subscribed_attributes = {
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
  },
  capability_handlers = {
  },
}

local matter_driver = MatterDriver("matter-smoke-co-alarm", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
