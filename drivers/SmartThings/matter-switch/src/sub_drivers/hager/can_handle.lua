-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
    local device_lib = require "st.device"
    local get_product_override_field = require "switch_utils.utils".get_product_override_field

    local checked_device = device.network_type == device_lib.NETWORK_TYPE_MATTER and device or device:get_parent_device()
    if get_product_override_field(checked_device, "needs_hager_subdriver") then
        return true, require("sub_drivers.hager")
    end
    return false
end
