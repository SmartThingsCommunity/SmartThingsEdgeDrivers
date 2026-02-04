-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_fibaro_heat_controller(opts, driver, device, ...)
  local FINGERPRINTS = require("fibaro-heat-controller.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
      if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
          return true, require("fibaro-heat-controller")
      end
  end

  return false
end

return can_handle_fibaro_heat_controller
