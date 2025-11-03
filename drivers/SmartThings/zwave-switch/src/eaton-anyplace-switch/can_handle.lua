local fingerprints = require("eaton-anyplace-switch.fingerprints")

local function can_handle_eaton_anyplace_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      local subdriver = require("eaton-anyplace-switch")
      return true, subdriver
    end
  end
  return false
end

return can_handle_eaton_anyplace_switch