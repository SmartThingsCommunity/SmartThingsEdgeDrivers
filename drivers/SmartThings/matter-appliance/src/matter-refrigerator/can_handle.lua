-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_matter_refrigerator(opts, driver, device)
  local REFRIGERATOR_DEVICE_TYPE_ID = 0x0070
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == REFRIGERATOR_DEVICE_TYPE_ID then
        return true, require("matter-refrigerator")
      end
    end
  end
  return false
end

return is_matter_refrigerator
