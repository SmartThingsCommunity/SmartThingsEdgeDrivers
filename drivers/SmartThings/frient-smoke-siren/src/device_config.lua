local FRIENT_DEVICE_FINGERPRINTS = {
  { mfr = "frient A/S", model = "SMSZB-120", subdriver = "smoke", ENDPOINT_SIREN = 0x23, ENDPOINT_TEMPERATURE = 0x26,
    ENDPOINT_TAMPER = 0x23 } -- Siren, Temperature, Smoke
}

return FRIENT_DEVICE_FINGERPRINTS
