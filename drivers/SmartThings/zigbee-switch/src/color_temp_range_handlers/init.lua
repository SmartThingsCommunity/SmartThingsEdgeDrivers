-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local switch_utils = require "switch_utils"

-- These values are a "sanity check" to ensure that max/min values we are getting are reasonable
local COLOR_TEMPERATURE_MIRED_MAX = 1000 -- 1000 Kelvin
local COLOR_TEMPERATURE_MIRED_MIN = 67 -- 15000 Kelvin

local function color_temp_min_mireds_handler(driver, device, value, zb_rx)
  -- if mired value is nil or outside of sane bounds, log and ignore. Else, save value
  local min_mired_bound = value.value
  if min_mired_bound == nil then
    return
  elseif (min_mired_bound < COLOR_TEMPERATURE_MIRED_MIN or min_mired_bound > COLOR_TEMPERATURE_MIRED_MAX) then
    device.log.warn_with({hub_logs = true}, string.format("Device reported a color temperature %d mired outside of sane range of %.2f-%.2f", min_mired_bound, COLOR_TEMPERATURE_MIRED_MIN, COLOR_TEMPERATURE_MIRED_MAX))
    return
  end
  device:set_field(switch_utils.MIRED_MIN_BOUND, min_mired_bound, {persist = true})

  -- if we have already received a valid max mired bound, emit a colorTemperatureRange event
  local max_mired_bound = device:get_field(switch_utils.MIRED_MAX_BOUND)
  if max_mired_bound == nil then
    return
  elseif min_mired_bound < max_mired_bound then
    local endpoint = zb_rx.address_header.src_endpoint.value
    local max_kelvin_bound = switch_utils.convert_mired_to_kelvin(min_mired_bound)
    local min_kelvin_bound = switch_utils.convert_mired_to_kelvin(max_mired_bound)
    device:emit_event_for_endpoint(endpoint, capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = min_kelvin_bound, maximum = max_kelvin_bound}}))
  else
    device.log.warn_with({hub_logs = true}, string.format("Device reported a max color temperature %d Mireds that is not higher than the reported min color temperature %d Mireds", max_mired_bound, min_mired_bound))
  end
end

local function color_temp_max_mireds_handler(driver, device, value, zb_rx)
  -- if mired value is nil or outside of sane bounds, log and ignore. Else, save value
  local max_mired_bound = value.value
  if max_mired_bound == nil then
    return
  elseif (max_mired_bound < COLOR_TEMPERATURE_MIRED_MIN or max_mired_bound > COLOR_TEMPERATURE_MIRED_MAX) then
    device.log.warn_with({hub_logs = true}, string.format("Device reported a color temperature %d mired outside of sane range of %.2f-%.2f", max_mired_bound, COLOR_TEMPERATURE_MIRED_MIN, COLOR_TEMPERATURE_MIRED_MAX))
    return
  end
  device:set_field(switch_utils.MIRED_MAX_BOUND, max_mired_bound, {persist = true})

  -- if we have already received a valid min mired bound, emit a colorTemperatureRange event
  local min_mired_bound = device:get_field(switch_utils.MIRED_MIN_BOUND)
  if min_mired_bound == nil then
    return
  elseif max_mired_bound > min_mired_bound then
    local endpoint = zb_rx.address_header.src_endpoint.value
    local max_kelvin_bound = switch_utils.convert_mired_to_kelvin(min_mired_bound)
    local min_kelvin_bound = switch_utils.convert_mired_to_kelvin(max_mired_bound)
    device:emit_event_for_endpoint(endpoint, capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = min_kelvin_bound, maximum = max_kelvin_bound}}))
  else
    device.log.warn_with({hub_logs = true}, string.format("Device reported a min color temperature %d Mireds that is not lower than the reported max color temperature %d Mireds", min_mired_bound, max_mired_bound))
  end
end

local color_temp_range_handlers = {
  NAME = "Color temp range handlers",
  zigbee_handlers = {
    attr = {
      [clusters.ColorControl.ID] = {
        [clusters.ColorControl.attributes.ColorTempPhysicalMinMireds.ID] = color_temp_min_mireds_handler,
        [clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds.ID] = color_temp_max_mireds_handler
      }
    }
  },
  can_handle = require("color_temp_range_handlers.can_handle")
}

return color_temp_range_handlers
