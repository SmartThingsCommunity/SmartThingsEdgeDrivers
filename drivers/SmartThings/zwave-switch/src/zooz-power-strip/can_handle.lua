-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local function can_handle_zooz_power_strip(opts, driver, device, ...)
  local fingerprints = {
    {mfr = 0x015D, prod = 0x0651, model = 0xF51C} -- Zooz ZEN 20 Power Strip
  }
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("zooz-power-strip")
      return true, subdriver
    end
  end
  return false
end

return can_handle_zooz_power_strip
