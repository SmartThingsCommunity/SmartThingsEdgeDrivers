local fingerprints = require("fibaro-single-switch.fingerprints")

local function can_handle_fibaro_single_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("fibaro-single-switch")
      return true, subdriver
    end
  end
  return false
end

return can_handle_fibaro_single_switch