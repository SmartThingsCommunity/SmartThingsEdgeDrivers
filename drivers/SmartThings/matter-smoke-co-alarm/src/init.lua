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

local function device_init(driver, device)
  device:subscribe()
end

local function device_added(driver, device)
  -- device:send(clusters.Thermostat.attributes.ControlSequenceOfOperation:read(device))
  -- device:send(clusters.FanControl.attributes.FanModeSequence:read(device))
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

local function smoke_state_event_handler(driver, device, ib, response)
  local state = ib.data.value
  if state == 0 then -- normal
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smokeDetector.smoke.clear())
  elseif state == 1 or state == 2 then -- warning or critical
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smokeDetector.smoke.detected())
  end
end

local function co_state_event_handler(driver, device, ib, response)
  local state = ib.data.value
  if state == 0 then -- normal
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smokeDetector.carbonMonoxideDetector.clear())
  elseif state == 1 or state == 2 then -- warning or critical
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smokeDetector.carbonMonoxideDetector.detected())
  end
end

local function hardware_fault_alert_event_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.tamperAlert.tamper.detected())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.tamperAlert.tamper.clear())
  end
end

local function test_in_progress_event_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, ccapabilities.smokeDetector.smoke.tested())
    device:emit_event_for_endpoint(ib.endpoint_id, ccapabilities.smokeDetector.carbonMonoxideDetector.tested())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, ccapabilities.smokeDetector.smoke.clear())
    device:emit_event_for_endpoint(ib.endpoint_id, ccapabilities.smokeDetector.carbonMonoxideDetector.clear())
  end
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
  },
  matter_handlers = {
    attr = {
      [clusters.SmokeCoAlarm.ID] = {
        [clusters.SmokeCoAlarm.attributes.SmokeState.ID] = smoke_state_event_handler,
        [clusters.SmokeCoAlarm.attributes.COState.ID] = co_state_event_handler,
        [clusters.SmokeCoAlarm.attributes.TestInProgress.ID] = test_in_progress_event_handler,
        [clusters.SmokeCoAlarm.attributes.HardwareFaultAlert.ID] = hardware_fault_alert_event_handler,
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler(capabilities.temperatureMeasurement.temperature),
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = humidity_attr_handler
      }
    }
  },
  subscribed_attributes = {
    [capabilities.smokeDetector.ID] = {
      clusters.SmokeCoAlarm.attributes.SmokeState,
      clusters.SmokeCoAlarm.attributes.TestInProgress,
    },
    [capabilities.carbonMonoxideDetector.ID] = {
      clusters.SmokeCoAlarm.attributes.COState,
      clusters.SmokeCoAlarm.attributes.TestInProgress, -- is it possible?
    },
    [capabilities.tamperAlert.ID] = {
      clusters.SmokeCoAlarm.attributes.HardwareFaultAlert
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.Thermostat.attributes.LocalTemperature,
      clusters.TemperatureMeasurement.attributes.MeasuredValue
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    }
  },
  capability_handlers = {
  },
}

local matter_driver = MatterDriver("matter-smoke-co-alarm", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
