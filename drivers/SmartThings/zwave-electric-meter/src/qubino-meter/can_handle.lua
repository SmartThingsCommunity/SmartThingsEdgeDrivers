-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_qubino_meter(opts, driver, device, ...)
  local FINGERPRINTS = require("qubino-meter.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("qubino-meter")
    end
  end
  return false
end

return can_handle_qubino_meter
