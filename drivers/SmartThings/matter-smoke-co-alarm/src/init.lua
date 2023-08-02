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

local batteryAlertID = "spacewonder52282.batteryAlert"
local deviceMutedID = "spacewonder52282.deviceMuted"
local endOfServiceAlertID = "spacewonder52282.endOfServiceAlert"
local expressedStateID = "spacewonder52282.expressedState"
local batteryAlert = capabilities[batteryAlertID]
local deviceMuted = capabilities[deviceMutedID]
local endOfServiceAlert = capabilities[endOfServiceAlertID]
local expressedState = capabilities[expressedStateID]

local function device_init(driver, device)
  device:subscribe()
end

local function device_added(driver, device)
  device:send(clusters.SmokeCoAlarm.attributes.ExpressedState:read(device))
  device:send(clusters.SmokeCoAlarm.attributes.SmokeState:read(device))
  device:send(clusters.SmokeCoAlarm.attributes.COState:read(device))
  device:send(clusters.SmokeCoAlarm.attributes.BatteryAlert:read(device))
  device:send(clusters.SmokeCoAlarm.attributes.DeviceMuted:read(device))
  device:send(clusters.SmokeCoAlarm.attributes.TestInProgress:read(device))
  device:send(clusters.SmokeCoAlarm.attributes.HardwareFaultAlert:read(device))
  device:send(clusters.SmokeCoAlarm.attributes.EndOfServiceAlert:read(device))
  device:send(clusters.TemperatureMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue:read(device))
end

-- Matter Handlers --
local function expressed_state_event_handler(driver, device, ib, response)
  local state = ib.data.value
  if state == 0 then -- Normal
    device:emit_event_for_endpoint(ib.endpoint_id, expressedState.expressedState.normal())
  elseif state == 1 then -- SmokeAlarm
    device:emit_event_for_endpoint(ib.endpoint_id, expressedState.expressedState.smokeAlarm())
  elseif state == 2 then -- COAlarm
    device:emit_event_for_endpoint(ib.endpoint_id, expressedState.expressedState.coAlarm())
  elseif state == 3 then -- BatteryAlert
    device:emit_event_for_endpoint(ib.endpoint_id, expressedState.expressedState.batteryAlert())
  elseif state == 4 then -- Testing
    device:emit_event_for_endpoint(ib.endpoint_id, expressedState.expressedState.testing())
  elseif state == 5 then -- HardwareFault
    device:emit_event_for_endpoint(ib.endpoint_id, expressedState.expressedState.hardwareFault())
  elseif state == 6 then -- EndOfService
    device:emit_event_for_endpoint(ib.endpoint_id, expressedState.expressedState.endOfService())
  elseif state == 7 then -- InterconnectSmoke
    device:emit_event_for_endpoint(ib.endpoint_id, expressedState.expressedState.interconnectSmoke())
  elseif state == 8 then -- InterconnectCO
    device:emit_event_for_endpoint(ib.endpoint_id, expressedState.expressedState.interconnectCO())
  end
end

local function smoke_state_event_handler(driver, device, ib, response)
  local state = ib.data.value
  if state == 0 then -- Normal
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smokeDetector.smoke.clear())
  elseif state == 1 or state == 2 then -- Warning or Critical
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smokeDetector.smoke.detected())
  end
end

local function co_state_event_handler(driver, device, ib, response)
  local state = ib.data.value
  if state == 0 then -- Normal
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
  elseif state == 1 or state == 2 then -- Warning or Critical
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.carbonMonoxideDetector.carbonMonoxide.detected())
  end
end

local function battery_alert_event_handler(driver, device, ib, response)
  local state = ib.data.value
  if state == 0 then -- Normal
    device:emit_event_for_endpoint(ib.endpoint_id, batteryAlert.batteryAlert.normal())
  elseif state == 1 then -- Warning
    device:emit_event_for_endpoint(ib.endpoint_id, batteryAlert.batteryAlert.warning())
  elseif state == 2 then -- Critical
    device:emit_event_for_endpoint(ib.endpoint_id, batteryAlert.batteryAlert.critical())
  end
end

local function device_muted_event_handler(driver, device, ib, response)
  local state = ib.data.value
  if state == 0 then -- NotMuted
    device:emit_event_for_endpoint(ib.endpoint_id, deviceMuted.deviceMuted.notMuted())
  elseif state == 1 then -- Muted
    device:emit_event_for_endpoint(ib.endpoint_id, deviceMuted.deviceMuted.muted())
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

local function hardware_fault_alert_event_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.tamperAlert.tamper.detected())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.tamperAlert.tamper.clear())
  end
end

local function end_of_service_alert_event_handler(driver, device, ib, response)
  local state = ib.data.value
  if state == 0 then -- Normal
    device:emit_event_for_endpoint(ib.endpoint_id, endOfServiceAlert.endOfServiceAlert.normal())
  elseif state == 1 then -- Expired
    device:emit_event_for_endpoint(ib.endpoint_id, endOfServiceAlert.endOfServiceAlert.expired())
  end
end

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
  local carbonMonoxide = math.floor(ib.data.value)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.carbonMonoxideMeasurement.carbonMonoxideLevel({value = carbonMonoxide, unit = "ppm"}))
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
  },
  matter_handlers = {
    attr = {
      [clusters.SmokeCoAlarm.ID] = {
        [clusters.SmokeCoAlarm.attributes.ExpressedState.ID] = expressed_state_event_handler,
        [clusters.SmokeCoAlarm.attributes.SmokeState.ID] = smoke_state_event_handler,
        [clusters.SmokeCoAlarm.attributes.COState.ID] = co_state_event_handler,
        [clusters.SmokeCoAlarm.attributes.BatteryAlert.ID] = battery_alert_event_handler,
        [clusters.SmokeCoAlarm.attributes.DeviceMuted.ID] = device_muted_event_handler,
        [clusters.SmokeCoAlarm.attributes.TestInProgress.ID] = test_in_progress_event_handler,
        [clusters.SmokeCoAlarm.attributes.HardwareFaultAlert.ID] = hardware_fault_alert_event_handler,
        [clusters.SmokeCoAlarm.attributes.EndOfServiceAlert.ID] = end_of_service_alert_event_handler,
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler(capabilities.temperatureMeasurement.temperature),
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = humidity_attr_handler
      },
      [clusters.CarbonMonoxideConcentrationMeasurement.ID] = {
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue.ID] = carbon_monoxide_attr_handler
      }
    }
  },
  subscribed_attributes = {
    [expressedStateID] = {
      clusters.SmokeCoAlarm.attributes.ExpressedState
    },
    [capabilities.smokeDetector.ID] = {
      clusters.SmokeCoAlarm.attributes.SmokeState,
      clusters.SmokeCoAlarm.attributes.TestInProgress,
    },
    [capabilities.carbonMonoxideDetector.ID] = {
      clusters.SmokeCoAlarm.attributes.COState,
      clusters.SmokeCoAlarm.attributes.TestInProgress, -- is it possible?
    },
    [batteryAlertID] = {
      clusters.SmokeCoAlarm.attributes.BatteryAlert
    },
    [deviceMutedID] = {
      clusters.SmokeCoAlarm.attributes.DeviceMuted
    },
    [capabilities.tamperAlert.ID] = {
      clusters.SmokeCoAlarm.attributes.HardwareFaultAlert
    },
    [endOfServiceAlertID] = {
      clusters.SmokeCoAlarm.attributes.EndOfServiceAlert
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.Thermostat.attributes.LocalTemperature,
      clusters.TemperatureMeasurement.attributes.MeasuredValue
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.carbonMonoxideMeasurement.ID] = {
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue
    }
  },
  capability_handlers = {
  },
}

local matter_driver = MatterDriver("matter-smoke-co-alarm", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
