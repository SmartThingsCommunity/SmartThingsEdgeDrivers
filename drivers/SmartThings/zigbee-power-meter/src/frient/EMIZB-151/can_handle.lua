-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_frient_power_meter = function(opts, driver, device, zb_rx)
  local FINGERPRINTS = require("frient.EMIZB-151.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return true, require("frient.EMIZB-151")
    end
  end

  return false
end

return is_frient_power_meter
