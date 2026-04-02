-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_aqara_products = function(opts, driver, device, ...)
    local FINGERPRINTS = { mfr = "aqara", model = "lumi.motion.ac01" }

    if device:get_manufacturer() == FINGERPRINTS.mfr and device:get_model() == FINGERPRINTS.model then
        return true, require("aqara")
    end
    return false
end

return is_aqara_products
