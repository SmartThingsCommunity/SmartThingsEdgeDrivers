-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local st_utils = require "st.utils"

local switch_utils = {}

switch_utils.MIRED_MAX_BOUND = "__max_mired_bound"
switch_utils.MIRED_MIN_BOUND = "__min_mired_bound"

switch_utils.MIREDS_CONVERSION_CONSTANT = 1000000

switch_utils.convert_mired_to_kelvin = function(mired)
  return st_utils.round(switch_utils.MIREDS_CONVERSION_CONSTANT / mired)
end

switch_utils.emit_event_if_latest_state_missing = function(device, component, capability, attribute_name, value)
  if device:get_latest_state(component, capability.ID, attribute_name) == nil then
    device:emit_event(value)
  end
end

return switch_utils
