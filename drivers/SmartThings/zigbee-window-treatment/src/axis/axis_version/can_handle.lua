-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_axis_gear_version = function(opts, driver, device)
  local SOFTWARE_VERSION = "software_version"
  local MIN_WINDOW_COVERING_VERSION = 1093
  local version = device:get_field(SOFTWARE_VERSION) or 0

  if version >= MIN_WINDOW_COVERING_VERSION then
    return true, require("axis.axis_version")
  end
  return false
end

return is_axis_gear_version
