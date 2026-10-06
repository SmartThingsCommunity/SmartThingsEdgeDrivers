-- Copyright 2026 Samjin
-- Licensed under the Apache License, Version 2.0

-- ThingsOne Presence Sensor (IC60001-PSC01): Matter occupancy, temperature, humidity, illuminance and battery
-- The attribute conversions follow the SmartThings matter-sensor driver.

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local MatterDriver = require "st.matter.driver"
local st_utils = require "st.utils"

-- SmartThings standard preference (0 disabled, 1 low, 2 medium, 3 high), labelled in the app language by the platform
local SENSITIVITY_PREF = "motionSensitivity"
-- motionSensitivity's own default; a setting never changed in the app reaches the driver empty
local SENSITIVITY_DEFAULT = 2
-- Device preference created in the developer account so its labels follow the app language (ko, en)
local OFF_DELAY_PREF = "publicguide63260.offDelay"
local OFF_DELAY_DEFAULT_S = 10
local OFF_DELAY_TIMER = "off_delay_timer"
local MODE_RETRIES = "operation_mode_retries"
local MODE_RETRY_LIMIT = 3
local MODE_ATTR = clusters.OccupancySensing.attributes.PIRUnoccupiedToOccupiedThreshold

local function cancel_off_delay(device)
  local timer = device:get_field(OFF_DELAY_TIMER)
  if timer ~= nil then
    device.thread:cancel_timer(timer)
    device:set_field(OFF_DELAY_TIMER, nil)
  end
end

local function occupancy_handler(driver, device, ib, response)
  -- Occupancy is a bitmap; bit 0 is "occupied"
  local occupied = ib.data.value ~= nil and (ib.data.value & 0x01) == 0x01
  local endpoint = ib.endpoint_id
  if occupied then
    cancel_off_delay(device)
    device:emit_event_for_endpoint(endpoint, capabilities.presenceSensor.presence("present"))
    return
  end
  -- A further 0 while the delay runs, from a refresh or a resubscription, keeps the original deadline
  if device:get_field(OFF_DELAY_TIMER) ~= nil then
    return
  end
  -- Hold "present" for the off delay, as the earlier ThingsOne driver did; a report of an already empty room passes at once
  local delay = tonumber((device.preferences or {})[OFF_DELAY_PREF]) or OFF_DELAY_DEFAULT_S
  if delay <= 0 or device:get_latest_state("main", capabilities.presenceSensor.ID, capabilities.presenceSensor.presence.NAME) ~= "present" then
    device:emit_event_for_endpoint(endpoint, capabilities.presenceSensor.presence("not present"))
    return
  end
  device:set_field(OFF_DELAY_TIMER, device.thread:call_with_delay(delay, function()
    device:set_field(OFF_DELAY_TIMER, nil)
    device:emit_event_for_endpoint(endpoint, capabilities.presenceSensor.presence("not present"))
  end))
end

local function temperature_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperature({value = ib.data.value / 100.0, unit = "C"}))
  end
end

local function humidity_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(st_utils.round(ib.data.value / 100.0)))
  end
end

local function illuminance_handler(driver, device, ib, response)
  -- MeasuredValue = 10000 x log10(lux) + 1, and 0 means below 1 lux
  if ib.data.value ~= nil then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.illuminanceMeasurement.illuminance(math.floor(10 ^ ((ib.data.value - 1) / 10000))))
  end
end

local function battery_handler(driver, device, ib, response)
  -- BatPercentRemaining is in half-percent steps
  if ib.data.value ~= nil then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

-- The firmware reads PIRUnoccupiedToOccupiedThreshold as its operation mode: 1 low power, 2 normal, 3 high power
local function wanted_mode(device)
  local level = tonumber((device.preferences or {})[SENSITIVITY_PREF]) or SENSITIVITY_DEFAULT
  -- "Disabled" (0) has no firmware mode, so the lowest one stands in for it
  return math.max(1, math.min(3, math.floor(level)))
end

local function write_mode(device, mode)
  local ep = device:get_endpoints(clusters.OccupancySensing.ID)[1] or 1
  device:send(MODE_ATTR:write(device, ep, mode))
  -- The report answering this read is checked against the setting in mode_handler
  device:send(MODE_ATTR:read(device))
end

-- The app setting is the reference: a device value that differs is rewritten, at most MODE_RETRY_LIMIT times per setting
local function mode_handler(driver, device, ib, response)
  local wanted = wanted_mode(device)
  if ib.data.value == nil or ib.data.value == wanted then
    device:set_field(MODE_RETRIES, nil)
    return
  end
  local tries = device:get_field(MODE_RETRIES) or 0
  if tries >= MODE_RETRY_LIMIT then
    return
  end
  device:set_field(MODE_RETRIES, tries + 1)
  device.log.info(string.format("operation mode %d on the device, the setting wants %d: rewriting (try %d)", ib.data.value, wanted, tries + 1))
  write_mode(device, wanted)
end

local function device_init(driver, device)
  device:subscribe()
end

local function device_removed(driver, device)
  cancel_off_delay(device)
end

-- The platform applies the offset to emitted values, so re-read to show it before the next 600 s report
local function info_changed(driver, device, event, args)
  local old = (args.old_st_store or {}).preferences or {}
  local new = device.preferences or {}
  if new.tempOffset ~= nil and old.tempOffset ~= nil and new.tempOffset ~= old.tempOffset then
    device:send(clusters.TemperatureMeasurement.attributes.MeasuredValue:read(device))
  end
  if new.humidityOffset ~= nil and old.humidityOffset ~= nil and new.humidityOffset ~= old.humidityOffset then
    device:send(clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:read(device))
  end
  if new[SENSITIVITY_PREF] ~= old[SENSITIVITY_PREF] then
    device:set_field(MODE_RETRIES, nil)
    write_mode(device, wanted_mode(device))
  end
end

local driver_template = {
  lifecycle_handlers = {
    init = device_init,
    removed = device_removed,
    infoChanged = info_changed,
  },
  matter_handlers = {
    attr = {
      [clusters.OccupancySensing.ID] = {
        [clusters.OccupancySensing.attributes.Occupancy.ID] = occupancy_handler,
        [MODE_ATTR.ID] = mode_handler,
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temperature_handler,
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = humidity_handler,
      },
      [clusters.IlluminanceMeasurement.ID] = {
        [clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID] = illuminance_handler,
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = battery_handler,
      },
    },
  },
  subscribed_attributes = {
    [capabilities.presenceSensor.ID] = {clusters.OccupancySensing.attributes.Occupancy, MODE_ATTR},
    [capabilities.temperatureMeasurement.ID] = {clusters.TemperatureMeasurement.attributes.MeasuredValue},
    [capabilities.relativeHumidityMeasurement.ID] = {clusters.RelativeHumidityMeasurement.attributes.MeasuredValue},
    [capabilities.illuminanceMeasurement.ID] = {clusters.IlluminanceMeasurement.attributes.MeasuredValue},
    [capabilities.battery.ID] = {clusters.PowerSource.attributes.BatPercentRemaining},
  },
  supported_capabilities = {
    capabilities.presenceSensor,
    capabilities.temperatureMeasurement,
    capabilities.relativeHumidityMeasurement,
    capabilities.illuminanceMeasurement,
    capabilities.battery,
  },
}

local driver = MatterDriver("ic60001-psc01", driver_template)
driver:run()
