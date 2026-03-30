-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
return function(opts, driver, device, ...)
    local device_lib = require "st.device"
    local fields = require "switch_utils.fields"
    local vendor_overrides = fields.vendor_overrides

    if device.network_type == device_lib.NETWORK_TYPE_CHILD then
        local parent = device:get_parent_device()
        if parent
                and parent.network_type == device_lib.NETWORK_TYPE_MATTER
                and vendor_overrides[0x1285][parent.manufacturer_info.product_id]
        then
            return true, require("sub_drivers.Hager")
        end
        return false
    end

    if device.network_type == device_lib.NETWORK_TYPE_MATTER
            and device.manufacturer_info.vendor_id == 0x1285
            and vendor_overrides[0x1285][device.manufacturer_info.product_id]
    then
        return true, require("sub_drivers.Hager")
    end

    return false
end