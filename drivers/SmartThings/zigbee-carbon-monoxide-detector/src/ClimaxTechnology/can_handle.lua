-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_climax_technology_carbon_monoxide = function(opts, driver, device)
  local FINGERPRINTS = require("ClimaxTechnology.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("ClimaxTechnology")
    end
  end

  return false
end

return is_climax_technology_carbon_monoxide
