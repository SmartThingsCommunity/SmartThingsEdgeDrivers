local fingerprints = require("zwave-dual-switch.fingerprints")

local function can_handle_zwave_dual_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("zwave-dual-switch")
      return true, subdriver
    end
  end
  return false
end

return can_handle_zwave_dual_switch