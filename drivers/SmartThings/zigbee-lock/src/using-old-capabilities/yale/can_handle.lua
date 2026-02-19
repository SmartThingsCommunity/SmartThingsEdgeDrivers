-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device)
  if device:get_manufacturer() == "ASSA ABLOY iRevo" or device:get_manufacturer() == "Yale" then
    local subdriver = require("using-old-capabilities.yale")
    return true, subdriver
  end
  return false
end
