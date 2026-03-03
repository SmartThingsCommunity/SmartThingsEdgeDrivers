-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local zigbee_constants = require "st.zigbee.constants"
local SimpleMetering = require "st.zigbee.cluster".clusters.SimpleMetering
local configurations = require "configurations"

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

local function device_init(driver, device)
  device:set_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY, 1, {persist = true})
  device:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, 100, {persist = true})
end

local function read_metering_attributes(driver, device)
  device:send(SimpleMetering.attributes.Multiplier:read(device))
  device:send(SimpleMetering.attributes.Divisor:read(device))
end

local function handle_multiplier_response(driver, device, value, zb_rx)
  device:set_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY, value.value, {persist = true})
end

local function handle_divisor_response(driver, device, value, zb_rx)
  device:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, value.value, {persist = true})
end

local simple_metering_config_subdriver = {
  NAME = "Simple Metering Config",
  supported_capabilities = {
    capabilities.energyMeter,
    capabilities.powerMeter
  },
  zigbee_handlers = {
    attr = {
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler,
        [SimpleMetering.attributes.Multiplier.ID] = handle_multiplier_response,
        [SimpleMetering.attributes.Divisor.ID] = handle_divisor_response
      }
    }
  },
  lifecycle_handlers = {
    init = configurations.power_reconfig_wrapper(device_init),
    added = read_metering_attributes,
    doConfigure = read_metering_attributes
  },
  can_handle = require("simple-metering-config.can_handle")
}

return simple_metering_config_subdriver