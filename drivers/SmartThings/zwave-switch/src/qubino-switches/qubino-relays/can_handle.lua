-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local function can_handle_qubino_flush_relay(opts, driver, device, cmd, ...)
  local fingerprints = {
    {mfr = 0x0159, prod = 0x0002, model = 0x0051}, -- Qubino Flush 2 Relay
    {mfr = 0x0159, prod = 0x0002, model = 0x0052}, -- Qubino Flush 1 Relay
    {mfr = 0x0159, prod = 0x0002, model = 0x0053}  -- Qubino Flush 1D Relay
  }
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("qubino-switches.qubino-relays")
    end
  end
  return false
end

return can_handle_qubino_flush_relay
