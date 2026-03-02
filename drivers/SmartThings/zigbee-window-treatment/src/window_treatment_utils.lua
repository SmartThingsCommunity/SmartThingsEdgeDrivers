-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local window_treatment_utils = {}

window_treatment_utils.emit_event_if_latest_state_missing = function(device, component, capability, attribute_name, value)
  if device:get_latest_state(component, capability.ID, attribute_name) == nil then
    device:emit_event(value)
  end
end

return window_treatment_utils
