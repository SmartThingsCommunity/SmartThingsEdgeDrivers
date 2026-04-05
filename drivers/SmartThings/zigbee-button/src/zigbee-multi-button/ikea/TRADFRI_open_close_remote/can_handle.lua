-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
    if device:get_model() == "TRADFRI open/close remote" then
        return true, require("zigbee-multi-button.ikea.TRADFRI_open_close_remote")
    end
    return false
end
