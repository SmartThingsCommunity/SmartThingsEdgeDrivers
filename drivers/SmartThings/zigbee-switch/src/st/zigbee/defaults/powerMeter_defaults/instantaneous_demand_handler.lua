-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local constants = require "st.zigbee.constants"
local log = require "log"

--- Default handler for InstantaneousDemand attribute on SimpleMetering cluster
---
--- This converts the Int24 instantaneous demand into the powerMeter.power capability event.  This will
--- check the device for values set in the constants.SIMPLE_METERING_MULTIPLIER_KEY and
--- constants.SIMPLE_METERING_DIVISOR_KEY to convert the raw value to the correctly scaled values.  These
--- fields should be set by reading the values from the same cluster
---
--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param value st.zigbee.data_types.Int24 the value of the instantaneous demand
--- @param zb_rx st.zigbee.ZigbeeMessageRx the full message this report came in
return function(driver, device, value, zb_rx)
  local raw_value = value.value
  --- demand = demand received * Multipler/Divisor
  local multiplier = device:get_field(constants.SIMPLE_METERING_MULTIPLIER_KEY) or 1
  local divisor = device:get_field(constants.SIMPLE_METERING_DIVISOR_KEY) or 1

  if divisor == 0 then
    log.warn_with({ hub_logs = true }, "Simple metering divisor is 0; using 1 to avoid division by zero")
    divisor = 1
  end

  raw_value = raw_value * multiplier/divisor

  local raw_value_watts = raw_value * 1000
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.powerMeter.power({value = raw_value_watts, unit = "W" }))
end
