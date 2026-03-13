-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
local utils = require "st.utils"

local switch_utils = {}

switch_utils.KELVIN_MAX = "_max_kelvin"
switch_utils.KELVIN_MIN = "_min_kelvin"
switch_utils.MIREDS_CONVERSION_CONSTANT = 1000000
switch_utils.COLOR_TEMPERATURE_KELVIN_MAX = 15000
switch_utils.COLOR_TEMPERATURE_KELVIN_MIN = 1000
switch_utils.COLOR_TEMPERATURE_MIRED_MAX = utils.round(switch_utils.MIREDS_CONVERSION_CONSTANT/switch_utils.COLOR_TEMPERATURE_KELVIN_MIN) -- 1000
switch_utils.COLOR_TEMPERATURE_MIRED_MIN = utils.round(switch_utils.MIREDS_CONVERSION_CONSTANT/switch_utils.COLOR_TEMPERATURE_KELVIN_MAX) -- 67

switch_utils.emit_event_if_latest_state_missing = function(device, component, capability, attribute_name, value)
  if device:get_latest_state(component, capability.ID, attribute_name) == nil then
    device:emit_event(value)
  end
end

return switch_utils
