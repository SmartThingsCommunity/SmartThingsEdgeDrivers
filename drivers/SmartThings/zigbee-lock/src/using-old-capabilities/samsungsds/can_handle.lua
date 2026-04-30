-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device)
  if device:get_manufacturer() == "SAMSUNG SDS" then
    local subdriver = require("using-old-capabilities.samsungsds")
    return true, subdriver
  end
  return false
end
