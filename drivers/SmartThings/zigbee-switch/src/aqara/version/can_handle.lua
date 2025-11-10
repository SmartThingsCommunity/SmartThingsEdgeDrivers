-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function (opts, driver, device)
  local PRIVATE_MODE = "PRIVATE_MODE"
  local private_mode = device:get_field(PRIVATE_MODE) or 0
  local res = private_mode == 1
  if res then
    return res, require("aqara.version")
  else
    return res
  end
end
