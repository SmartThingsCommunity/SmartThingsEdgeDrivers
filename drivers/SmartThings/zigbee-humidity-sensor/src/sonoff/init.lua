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
  reportable_change = 1 -- 0.1 kPa for the standard MeasuredValue attribute
}

local function pressure_report_handler(driver, device, value, zb_rx)
  if value.value == nil then
    log.warn(string.format("SNZB-02M pressure report has no value: %s", tostring(value)))
    return
  end

  local pressure_value = value.value / 10.0
  log.debug(string.format("SNZB-02M pressure raw: %s, converted: %s kPa", tostring(value.value), tostring(pressure_value)))
  device:emit_event(capabilities.atmosphericPressureMeasurement.atmosphericPressure({value = pressure_value, unit = "kPa"}))
end

-- This init overrides the parent init, which loads model-specific configurations.lua entries.
local function device_init(driver, device)
  device:add_configured_attribute(PRESSURE_CONFIGURATION)
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
  can_handle = can_handle
}
