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

local CARBON_MONOXIDE_MEASUREMENT_UNIT = "CarbonMonoxideConcentrationMeasurement_unit"

local function device_init(driver, device)
  device:subscribe()
end

local function info_changed(self, device, event, args)
  if device.preferences then
    if device.preferences["certifiedpreferences.smokeSensorSensitivity"] ~= args.old_st_store.preferences["certifiedpreferences.smokeSensorSensitivity"] then
      local eps = device:get_endpoints(clusters.SmokeCoAlarm.ID)
      if #eps > 0 then
        local smokeSensorSensitivity = device.preferences["certifiedpreferences.smokeSensorSensitivity"]
        if smokeSensorSensitivity == 0 then -- High
          device:send(clusters.SmokeCoAlarm.attributes.SmokeSensitivityLevel:write(device, eps[1], clusters.SmokeCoAlarm.types.SensitivityEnum.HIGH))
        elseif smokeSensorSensitivity == 1 then -- Medium
          device:send(clusters.SmokeCoAlarm.attributes.SmokeSensitivityLevel:write(device, eps[1], clusters.SmokeCoAlarm.types.SensitivityEnum.STANDARD))
        elseif smokeSensorSensitivity == 2 then -- Low
          device:send(clusters.SmokeCoAlarm.attributes.SmokeSensitivityLevel:write(device, eps[1], clusters.SmokeCoAlarm.types.SensitivityEnum.LOW))
        end
      end
    end
  end
end

-- Matter Handlers --
local function binary_state_handler_factory(zeroEvent, nonZeroEvent)
  return function(driver, device, ib, response)
    if ib.data.value == 0 and zeroEvent ~= nil then
      device:emit_event_for_endpoint(ib.endpoint_id, zeroEvent)
    elseif nonZeroEvent ~= nil then
      device:emit_event_for_endpoint(ib.endpoint_id, nonZeroEvent)
    end
  end
end

local function bool_handler_factory(trueEvent, falseEvent)
  return function(driver, device, ib, response)
    if ib.data.value and trueEvent ~= nil then
      device:emit_event_for_endpoint(ib.endpoint_id, trueEvent)
    elseif falseEvent ~= nil then
      device:emit_event_for_endpoint(ib.endpoint_id, falseEvent)
    end
  end
end

local function test_in_progress_event_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smokeDetector.smoke.tested())
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.carbonMonoxideDetector.carbonMonoxide.tested())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smokeDetector.smoke.clear())
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
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

local function carbon_monoxide_attr_handler(driver, device, ib, response)
  local value = ib.data.value
  local unit = device:get_field(CARBON_MONOXIDE_MEASUREMENT_UNIT)
  if unit == clusters.CarbonMonoxideConcentrationMeasurement.types.MeasurementUnitEnum.PPB then
    value = value / 1000
  elseif unit == clusters.CarbonMonoxideConcentrationMeasurement.types.MeasurementUnitEnum.PPT then
    value = value / 1000000
  end
  value = math.floor(value)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.carbonMonoxideMeasurement.carbonMonoxideLevel({value = value, unit = "ppm"}))
end

local function carbon_monoxide_unit_attr_handler(driver, device, ib, response)
  local unit = ib.data.value
  device:set_field(CARBON_MONOXIDE_MEASUREMENT_UNIT, unit, { persist = true })
end

local function battery_alert_attr_handler(driver, device, ib, response)
  if ib.data.value == clusters.SmokeCoAlarm.types.AlarmStateEnum.NORMAL then
    device:emit_event(capabilities.batteryLevel.battery.normal())
  elseif ib.data.value == clusters.SmokeCoAlarm.types.AlarmStateEnum.WARNING then
    device:emit_event(capabilities.batteryLevel.battery.warning())
  elseif ib.data.value == clusters.SmokeCoAlarm.types.AlarmStateEnum.CRITICAL then
    device:emit_event(capabilities.batteryLevel.battery.critical())
  end
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed
  },
  matter_handlers = {
    attr = {
      [clusters.SmokeCoAlarm.ID] = {
        [clusters.SmokeCoAlarm.attributes.SmokeState.ID] = binary_state_handler_factory(capabilities.smokeDetector.smoke.clear(), capabilities.smokeDetector.smoke.detected()),
        [clusters.SmokeCoAlarm.attributes.COState.ID] = binary_state_handler_factory(capabilities.carbonMonoxideDetector.carbonMonoxide.clear(), capabilities.carbonMonoxideDetector.carbonMonoxide.detected()),
        [clusters.SmokeCoAlarm.attributes.BatteryAlert.ID] = battery_alert_attr_handler,
        [clusters.SmokeCoAlarm.attributes.TestInProgress.ID] = test_in_progress_event_handler,
        [clusters.SmokeCoAlarm.attributes.HardwareFaultAlert.ID] = bool_handler_factory(capabilities.hardwareFault.hardwareFault.detected(), capabilities.hardwareFault.hardwareFault.clear()),
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler,
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = humidity_attr_handler
      },
      [clusters.CarbonMonoxideConcentrationMeasurement.ID] = {
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue.ID] = carbon_monoxide_attr_handler,
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = carbon_monoxide_unit_attr_handler,
      }
    },
  },
  subscribed_attributes = {
    [capabilities.smokeDetector.ID] = {
      clusters.SmokeCoAlarm.attributes.SmokeState,
      clusters.SmokeCoAlarm.attributes.TestInProgress,
    },
    [capabilities.carbonMonoxideDetector.ID] = {
      clusters.SmokeCoAlarm.attributes.COState,
      clusters.SmokeCoAlarm.attributes.TestInProgress,
    },
    [capabilities.hardwareFault.ID] = {
      clusters.SmokeCoAlarm.attributes.HardwareFaultAlert
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
    [capabilities.batteryLevel.ID] = {
      clusters.SmokeCoAlarm.attributes.BatteryAlert,
    }
  },
}

local matter_driver = MatterDriver("matter-smoke-co-alarm", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()