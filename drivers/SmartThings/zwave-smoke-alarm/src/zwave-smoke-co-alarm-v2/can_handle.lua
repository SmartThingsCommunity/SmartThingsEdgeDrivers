-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_v2_alarm(opts, driver, device, cmd, ...)
  local FINGERPRINTS = require("zwave-smoke-co-alarm-v2.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true, require("zwave-smoke-co-alarm-v2")
    end
  end
  return false
end

return can_handle_v2_alarm
