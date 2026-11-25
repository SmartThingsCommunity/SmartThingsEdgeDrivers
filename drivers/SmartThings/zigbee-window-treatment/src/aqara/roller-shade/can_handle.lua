-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local MODELS = {
  ["lumi.curtain.aq2"] = true,
  ["lumi.curtain.vagl02"] = true
}
local function roller_shade_can_handle(opts, driver, device, ...)
  if MODELS[device:get_model()] then
    return true, require("aqara.roller-shade")
  end
  return false
end

return roller_shade_can_handle
