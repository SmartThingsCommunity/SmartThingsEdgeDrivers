-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"

local function can_handle(opts, driver, device, ...)
  if device:supports_capability(capabilities.signalStrength, "main") then
    return true, require("range-extender-signal")
  end
  return false
end

return can_handle
