return function(opts, driver, device, ...)
  local FINGERPRINTS = require "wallhero.fingerprints"
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("wallhero")
      return true, subdriver
    end
  end
  return false
end

