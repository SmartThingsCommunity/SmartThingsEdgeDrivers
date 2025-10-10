
return function(opts, driver, device)
    local INOVELLI_VZM31_SN_FINGERPRINTS = {
  { mfr = "Inovelli", model = "VZM31-SN" }
}

  for _, fingerprint in ipairs(INOVELLI_VZM31_SN_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("inovelli-vzm31-sn")
      return true, subdriver
    end
  end
  return false
end
