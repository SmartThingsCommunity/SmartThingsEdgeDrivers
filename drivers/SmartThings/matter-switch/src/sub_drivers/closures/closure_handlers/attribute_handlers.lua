-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local closure_fields = require "sub_drivers.closures.closure_utils.fields"

local ClosureAttributeHandlers = {}

ClosureAttributeHandlers.current_pos_handler = function(attribute)
  return function(driver, device, ib, response)
    if ib.data.value == nil then return end
    local windowShade = capabilities.windowShade.windowShade
    local position = 100 - math.floor(ib.data.value / 100)
    local reverse = device:get_field(closure_fields.REVERSE_POLARITY)
    device:emit_event_for_endpoint(ib.endpoint_id, attribute(position))

    if attribute == capabilities.windowShadeLevel.shadeLevel then
      device:set_field(closure_fields.CURRENT_LIFT, position)
    else
      device:set_field(closure_fields.CURRENT_TILT, position)
    end

    local lift_position = device:get_field(closure_fields.CURRENT_LIFT)
    local tilt_position = device:get_field(closure_fields.CURRENT_TILT)

    if lift_position == nil then
      if tilt_position == 0 then
        device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.open() or windowShade.closed())
      elseif tilt_position == 100 then
        device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.closed() or windowShade.open())
      else
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.partially_open())
      end
    elseif lift_position == 100 then
      device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.closed() or windowShade.open())
    elseif lift_position > 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, windowShade.partially_open())
    elseif lift_position == 0 then
      if tilt_position == nil or tilt_position == 0 then
        device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.open() or windowShade.closed())
      elseif tilt_position > 0 then
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.partially_open())
      end
    end
  end
end

function ClosureAttributeHandlers.current_status_handler(driver, device, ib, response)
  local windowShade = capabilities.windowShade.windowShade
  local reverse = device:get_field(closure_fields.REVERSE_POLARITY)
  local state = ib.data.value & clusters.WindowCovering.types.OperationalStatus.GLOBAL
  if state == 1 then -- opening
    device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.closing() or windowShade.opening())
  elseif state == 2 then -- closing
    device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.opening() or windowShade.closing())
  elseif state ~= 0 then -- unknown
    device:emit_event_for_endpoint(ib.endpoint_id, windowShade.unknown())
  end
end

function ClosureAttributeHandlers.level_attr_handler(driver, device, ib, response)
  if ib.data.value == nil then return end
  local level = math.floor((ib.data.value / 254.0 * 100) + 0.5)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShadeLevel.shadeLevel(level))
end

return ClosureAttributeHandlers
