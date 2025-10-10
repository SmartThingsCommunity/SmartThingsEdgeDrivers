
return function(opts, driver, device)
  local AURORA_RELAY_FINGERPRINTS = {
    { mfr = "Aurora", model = "Smart16ARelay51AU" },
    { mfr = "Develco Products A/S", model = "Smart16ARelay51AU" },
    { mfr = "SALUS", model = "SX885ZB" }
  }
  for _, fingerprint in ipairs(AURORA_RELAY_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("zigbee-switch-power.aurora-relay")
    end
  end
  return false
end
