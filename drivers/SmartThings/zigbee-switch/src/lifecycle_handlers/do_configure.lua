-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
return function(self, device)
  local ZLL_PROFILE_ID = 0xC05E
  local version = require "version"
  if version.api < 16 or (version.api > 15 and device:get_profile_id() ~= ZLL_PROFILE_ID) then
    device:refresh()
  end
  device:configure()

  -- Additional one time configuration
  if device:supports_capability(capabilities.energyMeter) or device:supports_capability(capabilities.powerMeter) then
    local clusters = require "st.zigbee.zcl.clusters"
    -- Divisor and multipler for EnergyMeter
    device:send(clusters.SimpleMetering.attributes.Divisor:read(device))
    device:send(clusters.SimpleMetering.attributes.Multiplier:read(device))
  end
end
