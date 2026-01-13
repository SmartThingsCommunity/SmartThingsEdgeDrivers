-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_bosch_button_contact(opts, driver, device)
    local device_lib = require "st.device"
    local BOSCH_VENDOR_ID =  0x1209
    local BOSCH_PRODUCT_ID = 0x3015
    if device.network_type == device_lib.NETWORK_TYPE_MATTER and
    device.manufacturer_info.vendor_id == BOSCH_VENDOR_ID and
    device.manufacturer_info.product_id == BOSCH_PRODUCT_ID then
        return true, require("sub_drivers.bosch_button_contact")
    end
    return false
end

return is_bosch_button_contact
