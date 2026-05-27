-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_sinope_thermostat = function(opts, driver, device)
  local SINOPE_TECHNOLOGIES_MFR_STRING = "Sinope Technologies"
  if device:get_manufacturer() == SINOPE_TECHNOLOGIES_MFR_STRING then
    return true, require("sinope")
  else
    return false
  end
end

return is_sinope_thermostat
