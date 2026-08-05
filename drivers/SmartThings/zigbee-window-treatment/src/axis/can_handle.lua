-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_zigbee_window_shade = function(opts, driver, device)
  if device:get_manufacturer() == "AXIS" then
    return true, require("axis")
  end
  return false
end

return is_zigbee_window_shade
