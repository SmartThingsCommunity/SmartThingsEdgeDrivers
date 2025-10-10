return function(opts, driver, device)
  local ZLL_DIMMER_FINGERPRINTS = require("zigbee-dimming-light.zll-dimmer.fingerprints")
  for _, fingerprint in ipairs(ZLL_DIMMER_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("zigbee-dimming-light.zll-dimmer")
    end
  end
  return false
end
