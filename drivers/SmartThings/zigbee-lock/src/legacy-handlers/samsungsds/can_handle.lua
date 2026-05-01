-- Copyright 2026 SmartThings
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device)
  if device:get_manufacturer() == "SAMSUNG SDS" then
    local subdriver = require("legacy-handlers.samsungsds")
    return true, subdriver
  end
  return false
end
