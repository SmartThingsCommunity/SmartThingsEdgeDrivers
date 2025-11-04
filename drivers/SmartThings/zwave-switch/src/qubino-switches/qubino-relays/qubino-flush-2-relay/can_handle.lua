-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local QUBINO_FLUSH_2_RELAY_FINGERPRINT = { mfr = 0x0159, prod = 0x0002, model = 0x0051 }

local function can_handle_qubino_flush_2_relay(opts, driver, device, ...)
  
  if device:id_match(QUBINO_FLUSH_2_RELAY_FINGERPRINT.mfr, QUBINO_FLUSH_2_RELAY_FINGERPRINT.prod, QUBINO_FLUSH_2_RELAY_FINGERPRINT.model) then
    return true, require("qubino-switches.qubino-relays.qubino-flush-2-relay")
  end
  return false
end

return can_handle_qubino_flush_2_relay