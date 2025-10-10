return function(opts, driver, device)
  local DIMMING_LIGHT_FINGERPRINTS = require "zigbee-dimming-light.fingerprints"
  for _, fingerprint in ipairs(DIMMING_LIGHT_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("zigbee-dimming-light")
      return true, subdriver
    end
  end
  return false
end
