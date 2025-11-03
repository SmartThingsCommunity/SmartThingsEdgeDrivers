local fingerprints = require("zooz-zen-30-dimmer-relay.fingerprints")

local function can_handle_zooz_zen_30_dimmer_relay_double_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("zooz-zen-30-dimmer-relay")
      return true, subdriver
    end
  end
  return false
end

return can_handle_zooz_zen_30_dimmer_relay_double_switch