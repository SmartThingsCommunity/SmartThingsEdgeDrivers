-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_rtitek_sthzb(opts, driver, device)
  if device:get_manufacturer() == "Rti-Tek" and device:get_model() == "STHZB" then
    return true, require("rtitek-sthzb")
  end
  return false
end

return can_handle_rtitek_sthzb
