local fingerprints = require("eaton-accessory-dimmer.fingerprints")

local function can_handle_eaton_accessory_dimmer(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("eaton-accessory-dimmer")
      return true, subdriver
    end
  end
  return false
end

return can_handle_eaton_accessory_dimmer