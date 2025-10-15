return function(opts, driver, device)
  local FINGERPRINTS = require("aqara.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("aqara")
      return true, subdriver
    end
  end
  return false
end
