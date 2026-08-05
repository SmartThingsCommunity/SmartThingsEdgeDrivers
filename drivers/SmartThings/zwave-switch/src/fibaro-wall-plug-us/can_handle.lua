-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local function can_handle_fibaro_wall_plug(opts, driver, device, ...)
  local fingerprints = {
    {mfr = 0x010F, prod = 0x1401, model = 0x1001}, -- Fibaro Outlet
    {mfr = 0x010F, prod = 0x1401, model = 0x2000}, -- Fibaro Outlet
  }
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("fibaro-wall-plug-us")
      return true, subdriver
    end
  end
  return false
end

return can_handle_fibaro_wall_plug
