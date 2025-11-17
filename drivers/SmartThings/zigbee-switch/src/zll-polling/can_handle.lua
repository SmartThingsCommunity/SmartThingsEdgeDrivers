-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, zb_rx, ...)
  local constants = require "st.zigbee.constants"

  local endpoint = device.zigbee_endpoints[device.fingerprinted_endpoint_id] or device.zigbee_endpoints[tostring(device.fingerprinted_endpoint_id)]
  if (endpoint ~= nil and endpoint.profile_id == constants.ZLL_PROFILE_ID) then
    local subdriver = require("zll-polling")
    return true, subdriver
  else
    return false
  end
end
