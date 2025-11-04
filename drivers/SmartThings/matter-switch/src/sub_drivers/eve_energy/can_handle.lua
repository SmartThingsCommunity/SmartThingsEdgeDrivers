-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device )
  local EVE_MANUFACTURER_ID = 0x130A
  if device.network_type == require("st.device").NETWORK_TYPE_MATTER and
    device.manufacturer_info.vendor_id == EVE_MANUFACTURER_ID then
    return true, require("sub_drivers.eve_energy")
  end
  return false
end
