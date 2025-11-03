local fingerprints = require("aeon-smart-strip.fingerprints")

--- Determine whether the passed device is Aeon smart strip
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_aeon_smart_strip(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("aeon-smart-strip")
      return true, subdriver
    end
  end
  return false
end


return can_handle_aeon_smart_strip