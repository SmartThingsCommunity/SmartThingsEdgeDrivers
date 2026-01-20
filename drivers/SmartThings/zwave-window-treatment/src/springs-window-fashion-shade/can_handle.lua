-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_springs_window_fashion_shade(opts, driver, device, ...)
  local FINGERPRINTS = require("springs-window-fashion-shade.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match( fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("springs-window-fashion-shade")
    end
  end
  return false
end

return can_handle_springs_window_fashion_shade
