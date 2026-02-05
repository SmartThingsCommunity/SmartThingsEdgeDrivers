-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local LOCK_WITHOUT_CODES_FINGERPRINTS = {
    { model = "E261-KR0B0Z0-HA" },
    { mfr = "Danalock",         model = "V3-BTZB" }
}

return function(opts, driver, device, cmd)
    for _, fingerprint in ipairs(LOCK_WITHOUT_CODES_FINGERPRINTS) do
        if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
            local subdriver = require("using-old-capabilities.lock-without-codes")
            return true, subdriver
        end
    end
    return false
end
