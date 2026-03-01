-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local can_handle_simple_metering_config = function(opts, driver, device)
  return device.fingerprinted == true
end

return can_handle_simple_metering_config