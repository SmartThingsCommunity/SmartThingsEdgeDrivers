-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"

return function(opts, driver, device)
  local can_handle = device:supports_capability(capabilities.statelessWindowShadeLevelStep)
  if can_handle then
    local subdriver = require("stateless_handler")
    return true, subdriver
  end
  return false
end
