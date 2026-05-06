-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local st_utils = require "st.utils"

local switch_utils = {}

switch_utils.MIRED_MAX_BOUND = "__max_mired_bound"
switch_utils.MIRED_MIN_BOUND = "__min_mired_bound"

-- Fields to store the transition times for the stateless capabilities,
-- in case native handler implementations need to be re-configured in the future
switch_utils.SWITCH_LEVEL_STEP_TRANSITION_TIME = "__switch_level_step_transition_time"
switch_utils.COLOR_TEMP_STEP_TRANSITION_TIME = "__color_temp_step_transition_time"

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
