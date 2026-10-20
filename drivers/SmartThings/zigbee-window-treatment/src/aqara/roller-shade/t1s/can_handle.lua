-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function t1s_can_handle(opts, driver, device, ...)
  if device:get_model() == "lumi.curtain.vagl02" then
    return true, require("aqara.roller-shade.t1s")
  end
  return false
end

return t1s_can_handle
