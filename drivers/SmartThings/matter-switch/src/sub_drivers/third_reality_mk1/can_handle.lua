-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local utils = require "switch_utils.utils"

return function(opts, driver, device)
  if utils.get_product_override_field(device, "is_third_reality_mk1") then
    return true, require("sub_drivers.third_reality_mk1")
  end
  return false
end
