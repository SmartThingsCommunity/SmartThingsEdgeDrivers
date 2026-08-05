-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Determine whether the passed device is an Aeotec LED Bulb 6.
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device is an Aeotec LED Bulb 6, else false
local function is_aeotec_led_bulb_6(opts, driver, device, ...)
    local AEOTEC_MFR_ID = 0x0371
    local AEOTEC_LED_BULB_6_PRODUCT_TYPE_US = 0x0103
    local AEOTEC_LED_BULB_6_PRODUCT_TYPE_EU = 0x0003
    local AEOTEC_LED_BULB_6_PRODUCT_ID = 0x0002
    if device:id_match(
        AEOTEC_MFR_ID,
        { AEOTEC_LED_BULB_6_PRODUCT_TYPE_US, AEOTEC_LED_BULB_6_PRODUCT_TYPE_EU },
        AEOTEC_LED_BULB_6_PRODUCT_ID) then
        return true, require("aeotec-led-bulb-6")
    end
    return false
end

return is_aeotec_led_bulb_6
