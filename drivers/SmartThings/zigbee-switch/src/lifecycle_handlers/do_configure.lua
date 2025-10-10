
local capabilities = require "st.capabilities"
return function(self, device)
  device:refresh()
  device:configure()

  -- Additional one time configuration
  if device:supports_capability(capabilities.energyMeter) or device:supports_capability(capabilities.powerMeter) then
    local clusters = require "st.zigbee.zcl.clusters"
    -- Divisor and multipler for EnergyMeter
    device:send(clusters.SimpleMetering.attributes.Divisor:read(device))
    device:send(clusters.SimpleMetering.attributes.Multiplier:read(device))
  end
end
