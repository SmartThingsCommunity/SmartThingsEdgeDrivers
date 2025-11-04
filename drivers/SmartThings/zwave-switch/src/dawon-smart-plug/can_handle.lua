-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local fingerprints = require("dawon-smart-plug.fingerprints")

--- Determine whether the passed device is Dawon smart plug
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_dawon_smart_plug(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("dawon-smart-plug")
      return true, subdriver
    end
  end
  return false
end

return can_handle_dawon_smart_plug