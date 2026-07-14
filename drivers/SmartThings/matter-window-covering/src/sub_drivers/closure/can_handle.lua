-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local CLOSURE_CONTROL_CLUSTER_ID = 0x0104

return function(opts, driver, device)
  local embedded_cluster_utils = require "sub_drivers.closure.closure_utils.embedded_cluster_utils"
  if #embedded_cluster_utils.get_endpoints(device, CLOSURE_CONTROL_CLUSTER_ID) > 0 then
    return true, require("sub_drivers.closure")
  end
  return false
end
