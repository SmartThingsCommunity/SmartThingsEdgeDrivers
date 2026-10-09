-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_qubino_flush_shutter(opts, self, device, ...)
  local FINGERPRINTS = require("window-treatment-venetian.qubino-flush-shutter.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match( fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("window-treatment-venetian.qubino-flush-shutter")
    end
  end
  return false
end

return can_handle_qubino_flush_shutter
