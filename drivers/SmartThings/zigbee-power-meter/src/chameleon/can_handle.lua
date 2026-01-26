-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_chameleon_ct_clamp  = function(opts, driver, device)
  local FINGERPRINTS = require("chameleon.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
      if device:get_model() == fingerprint.model then
          return true, require("chameleon")
      end
  end

  return false
end

return is_chameleon_ct_clamp 
