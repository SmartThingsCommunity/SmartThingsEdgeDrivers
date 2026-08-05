-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_aqara_products = function(opts, driver, device)
    local FINGERPRINTS = require "aqara.fingerprints"
    if FINGERPRINTS[device:get_model()] and FINGERPRINTS[device:get_model()].mfr == device:get_manufacturer() then
        return true, require("aqara")
    end
    return false
end

return is_aqara_products
