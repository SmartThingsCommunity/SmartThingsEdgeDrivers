-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
    if device:get_model() == "TRADFRI remote control" then
        return true, require("zigbee-multi-button.ikea.TRADFRI_remote_control")
    end
    return false
end
