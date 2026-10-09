-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_aqara_products = function(opts, driver, device, ...)
    local FINGERPRINTS = { mfr = "LUMI", model = "lumi.remote.rkba01" }

    if device:get_manufacturer() == FINGERPRINTS.mfr and device:get_model() == FINGERPRINTS.model then
        return true, require("aqara-knob")
    end
    return false
end

return is_aqara_products
