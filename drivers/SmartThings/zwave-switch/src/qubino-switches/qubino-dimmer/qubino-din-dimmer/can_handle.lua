local function can_handle_qubino_din_dimmer(opts, driver, device, ...)
  -- Qubino Din Dimmer: mfr = 0x0159, prod = 0x0001, model = 0x0052
  if device:id_match(0x0159, 0x0001, 0x0052) then
    return true, require("qubino-switches.qubino-dimmer.qubino-din-dimmer")
  end
  return false
end

return can_handle_qubino_din_dimmer