-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
    if device:get_model() == "Situo 4 Zigbee" then
        return true, require("zigbee-multi-button.somfy.somfy_situo_4")
    end
    return false
end
