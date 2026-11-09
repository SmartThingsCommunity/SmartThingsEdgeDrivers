-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local can_handle_ikea = function(opts, driver, device)
  if device:get_manufacturer() == "IKEA of Sweden" then
    return true, require("ikea")
  end
  return false
end

return can_handle_ikea
