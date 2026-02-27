-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local utils = require "st.utils"
local KELVIN_MAX = "_max_kelvin"
local KELVIN_MIN = "_min_kelvin"
local MIREDS_CONVERSION_CONSTANT = 1000000
local COLOR_TEMPERATURE_KELVIN_MAX = 15000
local COLOR_TEMPERATURE_KELVIN_MIN = 1000
local COLOR_TEMPERATURE_MIRED_MAX = utils.round(MIREDS_CONVERSION_CONSTANT/COLOR_TEMPERATURE_KELVIN_MIN) -- 1000
local COLOR_TEMPERATURE_MIRED_MIN = utils.round(MIREDS_CONVERSION_CONSTANT/COLOR_TEMPERATURE_KELVIN_MAX) -- 67

local function color_temp_min_handler(driver, device, value, zb_rx)
  local temp_in_mired = value.value
  local endpoint = zb_rx.address_header.src_endpoint.value
  if temp_in_mired == nil then
    return
  end
  if (temp_in_mired < COLOR_TEMPERATURE_MIRED_MIN or temp_in_mired > COLOR_TEMPERATURE_MIRED_MAX) then
    device.log.warn_with({hub_logs = true}, string.format("Device reported a color temperature %d mired outside of sane range of %.2f-%.2f", temp_in_mired, COLOR_TEMPERATURE_MIRED_MIN, COLOR_TEMPERATURE_MIRED_MAX))
    return
  end
  local temp_in_kelvin = utils.round(MIREDS_CONVERSION_CONSTANT / temp_in_mired)
  device:set_field(KELVIN_MAX..endpoint, temp_in_kelvin)
  local min = device:get_field(KELVIN_MIN..endpoint)
  if min ~= nil then
    if temp_in_kelvin > min then
      device:emit_event_for_endpoint(endpoint, capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = min, maximum = temp_in_kelvin}}))
    else
      device.log.warn_with({hub_logs = true}, string.format("Device reported a min color temperature %d K that is not lower than the reported max color temperature %d K", min, temp_in_kelvin))
    end
  end
end

local function color_temp_max_handler(driver, device, value, zb_rx)
  local temp_in_mired = value.value
  local endpoint = zb_rx.address_header.src_endpoint.value
  if temp_in_mired == nil then
    return
  end
  if (temp_in_mired < COLOR_TEMPERATURE_MIRED_MIN or temp_in_mired > COLOR_TEMPERATURE_MIRED_MAX) then
    device.log.warn_with({hub_logs = true}, string.format("Device reported a color temperature %d mired outside of sane range of %.2f-%.2f", temp_in_mired, COLOR_TEMPERATURE_MIRED_MIN, COLOR_TEMPERATURE_MIRED_MAX))
    return
  end
  local temp_in_kelvin = utils.round(MIREDS_CONVERSION_CONSTANT / temp_in_mired)
  device:set_field(KELVIN_MIN..endpoint, temp_in_kelvin)
  local max = device:get_field(KELVIN_MAX..endpoint)
  if max ~= nil then
    if temp_in_kelvin < max then
      device:emit_event_for_endpoint(endpoint, capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = temp_in_kelvin, maximum = max}}))
    else
      device.log.warn_with({hub_logs = true}, string.format("Device reported a min color temperature %d K that is not lower than the reported max color temperature %d K", temp_in_kelvin, max))
    end
  end
end

local color_temp_range_handlers = {
  NAME = "Color temp range handlers",
  zigbee_handlers = {
    attr = {
      [clusters.ColorControl.ID] = {
        [clusters.ColorControl.attributes.ColorTempPhysicalMinMireds.ID] = color_temp_min_handler,
        [clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds.ID] = color_temp_max_handler
      }
    }
  },
  can_handle = require("color_temp_range_handlers.can_handle")
}

return color_temp_range_handlers
