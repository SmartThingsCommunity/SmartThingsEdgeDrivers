-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local switch_utils = require "switch_utils.utils"

return function(opts, driver, device)
  if switch_utils.get_product_override_field(device, "is_3r_mk1") then
    return true, require("sub_drivers.third_reality_mk1")
  end
  return false
end
