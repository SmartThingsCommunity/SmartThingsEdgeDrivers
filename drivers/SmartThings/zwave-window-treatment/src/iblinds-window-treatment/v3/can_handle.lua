-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Determine whether the passed device is iblinds window treatment v3
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @return boolean true if the device is iblinds window treatment, else false
local function can_handle_iblinds_window_treatment_v3(opts, driver, device, ...)
  local FINGERPRINTS = require("iblinds-window-treatment.v3.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("iblinds-window-treatment.v3")
    end
  end
  return false
end

return can_handle_iblinds_window_treatment_v3
