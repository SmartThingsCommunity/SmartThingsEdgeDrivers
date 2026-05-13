-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local CLOSURE_CONTROL_CLUSTER_ID = 0x0104

return function(opts, driver, device)
  if #device:get_endpoints(CLOSURE_CONTROL_CLUSTER_ID) > 0 then
    return true, require("sub_drivers.closure")
  end
  return false
end
