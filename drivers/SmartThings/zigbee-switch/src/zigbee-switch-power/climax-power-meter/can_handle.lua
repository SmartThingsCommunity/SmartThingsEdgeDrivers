-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device)
  if device:get_manufacturer() == "ClimaxTechnology" and device:get_model() == "PSM_00.00.00.35TC" then
    return true, require("zigbee-switch-power.climax-power-meter")
  end
  return false
end
