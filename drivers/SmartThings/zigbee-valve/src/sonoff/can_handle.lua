-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local FINGERPRINTS = {
  { mfr = "SONOFF", model = "SWV-ZFU" },
  { mfr = "SONOFF", model = "SWV-ZFE" },
  { mfr = "SONOFF", model = "SWV-ZNU" },
  { mfr = "SONOFF", model = "SWV-ZNE" },
}

local function sonoff_can_handle(opts, driver, device, ...)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true, require "sonoff"
    end
  end
  return false
end

return sonoff_can_handle
