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
  device:send(clusters.PowerSource.attributes.BatPercentRemaining:read(device))
end

local function info_changed(self, device, event, args)
  if device.preferences then
    if device.preferences["certifiedpreferences.smokeSensorSensitivity"] ~= args.old_st_store.preferences["certifiedpreferences.smokeSensorSensitivity"] then
      -- something like: device:send(smokeSensorSensitivity:write(valueConversionTable[newValue]))
    end
  end
end

-- Matter Handlers --
local function expressed_state_event_handler(driver, device, ib, response)
  local state = ib.data.value
  if state == 0 then -- Normal
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smokeDetector.smoke.clear())
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.tamperAlert.tamper.clear())
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.filterStatus.filterStatus.normal())
  elseif state == 1 then -- SmokeAlarm
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smokeDetector.smoke.detected())
  elseif state == 2 then -- COAlarm
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.carbonMonoxideDetector.carbonMonoxide.detected())
  elseif state == 3 then -- BatteryAlert
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.battery.battery(0))
  elseif state == 4 then -- Testing
		device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smokeDetector.smoke.tested())
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.carbonMonoxideDetector.carbonMonoxide.tested())
  elseif state == 5 then -- HardwareFault
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.tamperAlert.tamper.detected())
  elseif state == 6 then -- EndOfService
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.filterStatus.filterStatus.replace())
  elseif state == 7 then -- InterconnectSmoke
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smokeDetector.smoke.detected())
  elseif state == 8 then -- InterconnectCO
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.carbonMonoxideDetector.carbonMonoxide.detected())
  end
end

local function binary_state_handler_factory(zeroEvent, nonZeroEvent)
  return function(driver, device, ib, response)
    if ib.data.value == 0  and zeroEvent ~= nil then
      device:emit_event_for_endpoint(ib.endpoint_id, zeroEvent)
    elseif nonZeroEvent ~= nil then
      device:emit_event_for_endpoint(ib.endpoint_id, nonZeroEvent)
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
  local humidity = math.floor(ib.data.value / 100.0)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(humidity))
end

local function battery_percent_remaining_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = info_changed
  },
  matter_handlers = {
    attr = {
      [clusters.SmokeCoAlarm.ID] = {
        [clusters.SmokeCoAlarm.attributes.ExpressedState.ID] = expressed_state_event_handler,
        [clusters.SmokeCoAlarm.attributes.SmokeState.ID] = binary_state_handler_factory(capabilities.smokeDetector.smoke.clear(), capabilities.smokeDetector.smoke.detected()),
        [clusters.SmokeCoAlarm.attributes.COState.ID] = binary_state_handler_factory(capabilities.carbonMonoxideDetector.carbonMonoxide.clear(), capabilities.carbonMonoxideDetector.carbonMonoxide.detected()),
        [clusters.SmokeCoAlarm.attributes.BatteryAlert.ID] = binary_state_handler_factory(nil, capabilities.battery.battery(0)),
        [clusters.SmokeCoAlarm.attributes.DeviceMuted.ID] = binary_state_handler_factory(capabilities.audioMute.mute.unmuted(), capabilities.audioMute.mute.muted()),
        [clusters.SmokeCoAlarm.attributes.TestInProgress.ID] = test_in_progress_event_handler,
        [clusters.SmokeCoAlarm.attributes.HardwareFaultAlert.ID] = binary_state_handler_factory(capabilities.tamperAlert.tamper.clear(), capabilities.tamperAlert.tamper.detected()),
        [clusters.SmokeCoAlarm.attributes.EndOfServiceAlert.ID] = binary_state_handler_factory(capabilities.filterStatus.filterStatus.normal(), capabilities.filterStatus.filterStatus.replace()),
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler,
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = humidity_attr_handler
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = battery_percent_remaining_attr_handler
      }
    },
    event = {
      -- add the events (0x00-0x0A)
    }
  },
  subscribed_attributes = {
    [capabilities.smokeDetector.ID] = {
      clusters.SmokeCoAlarm.attributes.ExpressedState,
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.TemperatureMeasurement.attributes.MeasuredValue
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.battery.ID] = {
      clusters.PowerSource.attributes.BatPercentRemaining
    }
  },
  capability_handlers = {
    -- mute/unmute needs a handler
  },
}

local matter_driver = MatterDriver("matter-smoke-co-alarm", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
