local FRIENT_DEVICE_FINGERPRINTS = {
  { mfr = "frient A/S", model = "SMSZB-120", subdriver = "smoke", ENDPOINT_SIREN = 0x23, ENDPOINT_TEMPERATURE = 0x26,
    ENDPOINT_TAMPER = 0x23 }, -- Siren, Temperature, Smoke
  { mfr = "frient A/S", model = "SIRZB-110", subdriver = "siren", ENDPOINT_SIREN = 0x2B, ENDPOINT_TAMPER = 0x2B } -- Siren, Tamper
}

return FRIENT_DEVICE_FINGERPRINTS
