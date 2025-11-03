local fingerprints = require("aeotec-smart-switch.fingerprints")

local function can_handle(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, nil, fingerprint.prodId) then
      local subdriver = require("aeotec-smart-switch")
      return true, subdriver
    end
  end
  return false
end

return can_handle