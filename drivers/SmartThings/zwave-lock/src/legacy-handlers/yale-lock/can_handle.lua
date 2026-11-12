-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
  local yale_admin = require "yale-lock.admin"
  if device.zwave_manufacturer_id == yale_admin.MANUFACTURER_ID then
    return true, require("legacy-handlers.yale-lock")
  end
  return false
end
