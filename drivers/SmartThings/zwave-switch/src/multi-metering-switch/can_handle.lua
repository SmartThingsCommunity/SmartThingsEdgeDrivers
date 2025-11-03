local fingerprints = require("multi-metering-switch.fingerprints")

local function can_handle_multi_metering_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("multi-metering-switch")
      return true, subdriver
    end
  end
  return false
end

return can_handle_multi_metering_switch