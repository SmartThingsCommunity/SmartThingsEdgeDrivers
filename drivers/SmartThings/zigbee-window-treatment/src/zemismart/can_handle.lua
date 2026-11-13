-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"

local function can_handle(opts, driver, device)
  if device:get_manufacturer() == "_TZE200_cirjrpxe" and device:get_model() == "TS0301"
      and not device:supports_capability_by_id(capabilities.battery.ID) then
    return true, require("zemismart")
  end
  return false
end

return can_handle
