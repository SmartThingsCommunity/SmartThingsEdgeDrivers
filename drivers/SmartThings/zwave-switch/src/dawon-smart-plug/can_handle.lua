-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


--- Determine whether the passed device is Dawon smart plug
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_dawon_smart_plug(opts, driver, device, ...)
  local fingerprints = {
    {mfr = 0x018C, prod = 0x0042, model = 0x0005}, -- Dawon Smart Plug
    {mfr = 0x018C, prod = 0x0042, model = 0x0008} -- Dawon Smart Multitab
  }
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("dawon-smart-plug")
      return true, subdriver
    end
  end
  return false
end

return can_handle_dawon_smart_plug
