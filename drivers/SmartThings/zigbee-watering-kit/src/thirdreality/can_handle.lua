-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function thirdreality_can_handle(opts, driver, device, ...)
    if device:get_manufacturer() == "Third Reality, Inc" and device:get_model() == "3RWK0148Z" then
        return true, require("thirdreality")
    end
    return false
end

return thirdreality_can_handle
