-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local AEOTEC_HOME_ENERGY_METER_GEN8_FINGERPRINTS = {
  { mfr = 0x0371, prod = 0x0003, model = 0x0034 }, -- HEM Gen8 3 Phase EU
  { mfr = 0x0371, prod = 0x0102, model = 0x0034 }  -- HEM Gen8 3 Phase AU
}

local function can_handle_aeotec_meter_gen8_3_phase(opts, driver, device, ...)
  for _, fingerprint in ipairs(AEOTEC_HOME_ENERGY_METER_GEN8_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true, require("aeotec-home-energy-meter-gen8.3-phase")
    end
  end
  return false
end

return can_handle_aeotec_meter_gen8_3_phase
