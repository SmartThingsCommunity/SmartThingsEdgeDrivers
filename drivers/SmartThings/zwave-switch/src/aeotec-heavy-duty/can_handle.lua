-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle(opts, driver, device, ...)
  local fingerprints = {
    { mfr = 0x0086, model = 0x004E }
  }

  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, nil, fingerprint.model) then
      local subdriver = require("aeotec-heavy-duty")
      return true, subdriver
    end
  end
  return false
end

return can_handle
