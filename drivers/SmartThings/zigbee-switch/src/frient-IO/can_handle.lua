-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Function to determine if the driver can handle this device
return function(opts, driver, device, ...)
  if device:get_manufacturer() == "frient A/S" and device:get_model() == "IOMZB-110" then
    local subdriver = require("frient-IO")
    return true, subdriver
  else
    return false
  end
end
