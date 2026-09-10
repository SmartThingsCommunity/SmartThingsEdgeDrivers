-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local log = require "log"

local PressureMeasurement = clusters.PressureMeasurement

local PRESSURE_CONFIGURATION = {
  cluster = PressureMeasurement.ID,
  attribute = PressureMeasurement.attributes.MeasuredValue.ID,
  minimum_interval = 5,
  maximum_interval = 3600,
  data_type = PressureMeasurement.attributes.MeasuredValue.base_type,
  reportable_change = 50
}

local function convert_pressure_value(raw_value)
  if raw_value == nil then
    return nil
  end

  return raw_value / 10.0
end

local function pressure_report_handler(driver, device, value, zb_rx)
  local pressure_value = convert_pressure_value(value.value)
  if pressure_value == nil then
    log.warn(string.format("SNZB-02M pressure report has no value: %s", tostring(value)))
    return
  end

  log.debug(string.format("SNZB-02M pressure raw: %s, converted: %s kPa", tostring(value.value), tostring(pressure_value)))
  device:emit_event(capabilities.atmosphericPressureMeasurement.atmosphericPressure({value = pressure_value, unit = "kPa"}))
end

local function device_init(driver, device)
  device:add_configured_attribute(PRESSURE_CONFIGURATION)
end

local function refresh_handler(driver, device, command)
  device:send(clusters.TemperatureMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.RelativeHumidity.attributes.MeasuredValue:read(device))
  device:send(PressureMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local can_handle = require "sonoff.can_handle"

return {
  NAME = "Sonoff SNZB-02M Sensor",
  lifecycle_handlers = {
    init = device_init
  },
  zigbee_handlers = {
    attr = {
      [PressureMeasurement.ID] = {
        [PressureMeasurement.attributes.MeasuredValue.ID] = pressure_report_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler
    }
  },
  can_handle = can_handle
}
