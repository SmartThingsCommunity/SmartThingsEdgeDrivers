return function(opts, driver, device)
  local FINGERPRINTS = require("aqara.multi-switch.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("aqara.multi-switch")
    end
  end
  return false
end
