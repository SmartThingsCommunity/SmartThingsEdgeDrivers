-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device )
  if device.network_type == require("st.device").NETWORK_TYPE_MATTER then
    local name = string.format("%s", device.manufacturer_info.product_name)
    if string.find(name, "Aqara Cube T1 Pro") then
      return true, require("sub_drivers.aqara_cube")
    end
  end
  return false
end
