-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
    if device:get_model() == "lumi.motion.agl04" then
        return true, require("aqara.high-precision-motion")
    end
    return false
end
