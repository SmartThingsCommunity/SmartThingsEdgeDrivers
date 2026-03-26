-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device)
local ZIGBEE_METERING_PLUG_FINGERPRINTS = {
  { mfr = "REXENSE", model = "HY0105" }          -- HONYAR Outlet"
}
  for _, fingerprint in ipairs(ZIGBEE_METERING_PLUG_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("rexense")
      return true, subdriver
    end
  end

  return false
end
