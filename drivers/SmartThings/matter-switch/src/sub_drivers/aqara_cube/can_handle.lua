local device_lib = require "st.device"

local function is_aqara_cube(opts, driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then
    local name = string.format("%s", device.manufacturer_info.product_name)
    if string.find(name, "Aqara Cube T1 Pro") then
      return true, require("aqara_cube")
    end
  end
  return false
end

return is_aqara_cube