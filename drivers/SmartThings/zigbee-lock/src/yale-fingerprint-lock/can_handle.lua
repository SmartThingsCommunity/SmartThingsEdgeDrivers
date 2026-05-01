-- Copyright 2026 SmartThings
-- Licensed under the Apache License, Version 2.0

local YALE_FINGERPRINT_LOCK = {
  { mfr = "ASSA ABLOY iRevo", model = "iZBModule01" },
  { mfr = "ASSA ABLOY iRevo", model = "c700000202" },
  { mfr = "ASSA ABLOY iRevo", model = "0700000001" },
  { mfr = "ASSA ABLOY iRevo", model = "06ffff2027" }
}

return function(opts, driver, device)
  local capabilities = require "st.capabilities"
  local lock_codes_migrated = device:get_latest_state("main", capabilities.lockCodes.ID,
    capabilities.lockCodes.migrated.NAME, false)
  if not lock_codes_migrated then return false end
  for _, fingerprint in ipairs(YALE_FINGERPRINT_LOCK) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("yale-fingerprint-lock")
      return true, subdriver
    end
  end
  return false
end