-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_contact_sensor = function(opts, driver, device)
  if device:supports_capability(capabilities.contactSensor) then
    return true, require("contact")
  end
end

return is_contact_sensor
