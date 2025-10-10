return function(opts, driver, device)
  local FINGERPRINTS = require "multi-switch-no-master.fingerprints"
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model and (device:get_manufacturer() == nil or device:get_manufacturer() == fingerprint.mfr) then
      local subdriver = require("multi-switch-no-master")
      return true, subdriver
    end
  end
  return false
end
