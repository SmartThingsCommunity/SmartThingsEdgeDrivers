local EVE_MANUFACTURER_ID = 0x130A
local device_lib = require "st.device"

local function is_eve_energy_products(opts, driver, device)
  -- this sub driver does not support child devices
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and
      device.manufacturer_info.vendor_id == EVE_MANUFACTURER_ID then
    return true
  end

  return false
end

return is_eve_energy_products