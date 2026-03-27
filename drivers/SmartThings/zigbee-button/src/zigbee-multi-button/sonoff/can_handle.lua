-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function sonoff_can_handle(opts, driver, device, ...)
  local fingerprints = require("zigbee-multi-button.sonoff.fingerprints")

  for _, fingerprint in ipairs(fingerprints) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require("zigbee-multi-button.sonoff")
    end
  end

  return false
end

return sonoff_can_handle