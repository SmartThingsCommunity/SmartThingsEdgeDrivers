local device_lib = require "st.device"
local log = require "log"

local THIRD_REALITY_MK1_FINGERPRINT = { vendor_id = 0x1407, product_id = 0x1388 }

local function is_third_reality_mk1(opts, driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and
     device.manufacturer_info.vendor_id == THIRD_REALITY_MK1_FINGERPRINT.vendor_id and
     device.manufacturer_info.product_id == THIRD_REALITY_MK1_FINGERPRINT.product_id then
    log.info("Using Third Reality MK1 sub driver")
    return true
  end
  return false
end

return is_third_reality_mk1