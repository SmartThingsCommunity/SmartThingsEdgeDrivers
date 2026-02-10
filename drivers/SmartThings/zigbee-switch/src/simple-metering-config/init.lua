-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local zigbee_constants = require "st.zigbee.constants"
local SimpleMetering = require "st.zigbee.cluster".clusters.SimpleMetering

local function energy_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value

  if type(raw_value) ~= "number" or raw_value < 0 then
    return
  end

  local divisor = device:get_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY) or 100
  local multiplier = device:get_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY) or 1

  if divisor == 0 then
    return
  end

  local calculated_value = (raw_value * multiplier) / divisor

  device:emit_event_for_endpoint(
    zb_rx.address_header.src_endpoint.value,
    capabilities.energyMeter.energy({ value = calculated_value, unit = "kWh" })
  )
end

local simple_metering_config_subdriver = {
  supported_capabilities = {
    capabilities.energyMeter,
    capabilities.powerMeter
  },
  zigbee_handlers = {
    cluster = {
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      }
    }
  }
}

return simple_metering_config_subdriver