local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local ColorControl = clusters.ColorControl
local utils = require "st.utils"

local color_bounds = {}

local SANITY_CHECK_MIN_KELVIN = 1
local SANITY_CHECK_MAX_KELVIN = 30000
color_bounds.BOUND_RECEIVED = "colorTemp_bound_received"
color_bounds.MIN = "_MIN"
color_bounds.MAX = "_MAX"

color_bounds.mired_to_kelvin = function(value)
  local CONVERSION_CONSTANT = 1000000
  if value == 0 then value = 1 end -- shouldn't happen, but has
  -- we divide inside the rounding and multiply outside of it because we expect these
  -- bounds to be multiples of 100
  return utils.round((CONVERSION_CONSTANT / value) / 100) * 100
end

color_bounds.mired_bounds_handler_factory = function(minOrMax)
  return function(self, device, value, zb_rx)
    local endpoint_id = zb_rx.address_header.src_endpoint.value
    local temp_in_kelvin = color_bounds.mired_to_kelvin(value.value)
    if temp_in_kelvin > SANITY_CHECK_MIN_KELVIN and temp_in_kelvin < SANITY_CHECK_MAX_KELVIN then
      device:set_field(color_bounds.BOUND_RECEIVED..minOrMax, temp_in_kelvin)
    else
      device.log.warn("Device reported a min or max color temp value outside of reasonable bounds: "..temp_in_kelvin..'K')
    end

    local min = device:get_field(color_bounds.BOUND_RECEIVED..color_bounds.MIN)
    local max = device:get_field(color_bounds.BOUND_RECEIVED..color_bounds.MAX)
    if min ~= nil and max ~= nil and min < max then
      device:emit_event_for_endpoint(endpoint_id, capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = min, maximum = max}}))
      device:set_field(color_bounds.BOUND_RECEIVED..color_bounds.MAX, nil)
      device:set_field(color_bounds.BOUND_RECEIVED..color_bounds.MIN, nil)
    end
  end
end

color_bounds.check_bounds_if_applicable = function(device)
  if device:supports_capability(capabilities.colorTemperature) then
    device:send(ColorControl.attributes.ColorTempPhysicalMaxMireds:read(device))
    device:send(ColorControl.attributes.ColorTempPhysicalMinMireds:read(device))
  end
end

return color_bounds
