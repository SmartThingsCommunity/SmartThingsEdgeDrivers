-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


--- Determine whether the passed device is Dawon wall smart switch
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_dawon_wall_smart_switch(opts, driver, device, ...)
  local fingerprints = require("dawon-wall-smart-switch.fingerprints")
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("dawon-wall-smart-switch")
      return true, subdriver
    end
  end
  return false
end

return can_handle_dawon_wall_smart_switch
