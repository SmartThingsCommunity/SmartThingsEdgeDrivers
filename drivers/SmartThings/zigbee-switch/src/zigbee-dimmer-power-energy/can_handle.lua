local ZIGBEE_DIMMER_POWER_ENERGY_FINGERPRINTS = {
  { mfr = "Jasco Products", model = "43082" }
}

return function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_DIMMER_POWER_ENERGY_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("zigbee-dimmer-power-energy")
      return true, subdriver
    end
  end
  return false
end
