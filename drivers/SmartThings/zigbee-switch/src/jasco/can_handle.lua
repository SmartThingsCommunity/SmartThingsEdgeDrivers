return function(opts, driver, device)
    local JASCO_SWTICH_FINGERPRINTS = {
  { mfr = "Jasco Products", model = "43095" },
  { mfr = "Jasco Products", model = "43132" },
  { mfr = "Jasco Products", model = "43078" }
}

  for _, fingerprint in ipairs(JASCO_SWTICH_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("jasco")
      return true, subdriver
    end
  end
  return false
end
