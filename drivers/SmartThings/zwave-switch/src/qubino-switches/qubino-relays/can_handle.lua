local fingerprints = require("qubino-switches.qubino-relays.fingerprints")

local function can_handle_qubino_flush_relay(opts, driver, device, cmd, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("qubino-switches.qubino-relays")
    end
  end
  return false
end

return can_handle_qubino_flush_relay