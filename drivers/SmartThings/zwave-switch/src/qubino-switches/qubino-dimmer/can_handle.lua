local fingerprints = require("qubino-switches.qubino-dimmer.fingerprints")

local function can_handle_qubino_dimmer(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("qubino-switches.qubino-dimmer")
    end
  end
  return false
end

return can_handle_qubino_dimmer