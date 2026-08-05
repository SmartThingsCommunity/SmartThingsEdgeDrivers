-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local function can_handle_fibaro_double_switch(opts, driver, device, ...)
  local fingerprints = {
    {mfr = 0x010F, prod = 0x0203, model = 0x1000}, -- Fibaro Switch
    {mfr = 0x010F, prod = 0x0203, model = 0x2000}, -- Fibaro Switch
    {mfr = 0x010F, prod = 0x0203, model = 0x3000} -- Fibaro Switch
  }

  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("fibaro-double-switch")
      return true, subdriver
    end
  end
  return false
end

return can_handle_fibaro_double_switch
