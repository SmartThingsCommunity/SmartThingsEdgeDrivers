return function(opts, driver, device)
  local FINGERPRINTS = {
    { mfr = "LUMI", model = "lumi.light.acn004" },
    { mfr = "Aqara", model = "lumi.light.acn014" }
  }

  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("aqara-light")
      return true, subdriver
    end
  end
  return false
end
