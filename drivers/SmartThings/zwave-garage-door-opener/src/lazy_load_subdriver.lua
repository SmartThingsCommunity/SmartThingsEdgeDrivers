-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


return function(sub_driver_name)
  -- gets the current lua libs api version
  local ZwaveDriver = require "st.zwave.driver"
  local version = require "version"

  if version.api >= 16 then
    return ZwaveDriver.lazy_load_sub_driver_v2(sub_driver_name)
  elseif version.api >= 9 then
    return ZwaveDriver.lazy_load_sub_driver(require(sub_driver_name))
  else
    return require(sub_driver_name)
  end

end
