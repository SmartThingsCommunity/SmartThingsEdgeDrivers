-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device)
  local THIRD_REALITY_MK1_FINGERPRINT = { vendor_id = 0x1407, product_id = 0x1388 }
  if device.network_type == require("st.device").NETWORK_TYPE_MATTER and
    device.manufacturer_info.vendor_id == THIRD_REALITY_MK1_FINGERPRINT.vendor_id and
    device.manufacturer_info.product_id == THIRD_REALITY_MK1_FINGERPRINT.product_id then
    return true, require("sub_drivers.third_reality_mk1")
  end
  return false
end
