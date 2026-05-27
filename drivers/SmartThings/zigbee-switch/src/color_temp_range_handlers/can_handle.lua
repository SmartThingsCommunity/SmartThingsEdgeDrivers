-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"

return function(opts, driver, device)
  if device:supports_capability(capabilities.colorTemperature) then
    local subdriver = require("color_temp_range_handlers")
    return true, subdriver
  end
  return false
end
