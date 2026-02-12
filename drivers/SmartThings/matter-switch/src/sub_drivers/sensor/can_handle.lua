-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ib)
  local capabilities = require "st.capabilities"
  local supported_capabilities = {
    capabilities.illuminanceMeasurement,
    capabilities.motionSensor,
    capabilities.relativeHumidityMeasurement,
    capabilities.temperatureMeasurement,
  }
  -- MatterMessageDispatcher handles all events through a MATTER typed device.
  -- Therefore, find and check if an endpoint-mapped EDGE_CHILD device exists,
  -- Note: parameter ib should always be populated here by MatterMessageDispatcher.
  if opts and opts.dispatcher_class == "MatterMessageDispatcher" then
    local switch_utils = require "switch_utils.utils"
    if ib and ib.info_block and ib.info_block.endpoint_id then
      device = switch_utils.find_child(device, ib.info_block.endpoint_id) or device
    end
  end
  for _, capability in ipairs(supported_capabilities) do
    if device:supports_capability(capability) then
      return true, require("sub_drivers.sensor")
    end
  end
  return false
end
