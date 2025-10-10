return function(sub_driver_name)
  -- gets the current lua libs api version
  local version = require "version"
  local ZigbeeDriver = require "st.zigbee"
  if version.api >= 16 then
    return ZigbeeDriver.lazy_load_sub_driver_v2(sub_driver_name)
  elseif version.api >= 9 then
    return ZigbeeDriver.lazy_load_sub_driver(require(sub_driver_name))
  else
    return require(sub_driver_name)
  end
end
