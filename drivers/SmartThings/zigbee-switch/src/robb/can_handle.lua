return function(opts, driver, device)
local ROBB_DIMMER_FINGERPRINTS = {
  { mfr = "ROBB smarrt", model = "ROB_200-011-0" },
  { mfr = "ROBB smarrt", model = "ROB_200-014-0" }
}
  for _, fingerprint in ipairs(ROBB_DIMMER_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("robb")
      return true, subdriver
    end
  end
  return false
end

