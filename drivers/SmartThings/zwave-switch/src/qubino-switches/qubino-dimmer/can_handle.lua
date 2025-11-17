-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local function can_handle_qubino_dimmer(opts, driver, device, ...)
  local fingerprints = require("qubino-switches.qubino-dimmer.fingerprints")
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("qubino-switches.qubino-dimmer")
    end
  end
  return false
end

return can_handle_qubino_dimmer
