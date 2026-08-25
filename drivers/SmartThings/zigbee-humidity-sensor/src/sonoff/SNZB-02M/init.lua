--[[
Description: SNZB-02M pressure/humidity/temperature sensor driver
Version: 1.0
Author: GitHub Copilot
--]]

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local log = require "log"

local function convert_pressure_value(raw_value)
  if raw_value == nil then
    return nil
  end

  if raw_value > 2000 then
    return raw_value / 1000.0
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

local function refresh_handler(driver, device, command)
  device:send(clusters.TemperatureMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.RelativeHumidity.attributes.MeasuredValue:read(device))
  device:send(clusters.PressureMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local function can_handle(opts, driver, device)
  return device:get_model() == "SNZB-02M"
end

return {
  NAME = "Sonoff SNZB-02M Sensor",
  zigbee_handlers = {
    attr = {
      [clusters.PressureMeasurement.ID] = {
        [clusters.PressureMeasurement.attributes.MeasuredValue.ID] = pressure_report_handler
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
