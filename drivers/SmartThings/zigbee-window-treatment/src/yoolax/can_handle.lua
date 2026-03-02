-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_yoolax_window_shade(opts, driver, device)
  local FINGERPRINTS = require("yoolax.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("yoolax")
    end
  end
  return false
end

return is_yoolax_window_shade
