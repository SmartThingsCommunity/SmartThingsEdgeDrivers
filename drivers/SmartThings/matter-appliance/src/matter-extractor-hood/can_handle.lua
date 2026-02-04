-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_matter_extractor_hood(opts, driver, device)
  local EXTRACTOR_HOOD_DEVICE_TYPE_ID = 0x007A
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == EXTRACTOR_HOOD_DEVICE_TYPE_ID then
        return true, require("matter-extractor-hood")
      end
    end
  end
  return false
end

return is_matter_extractor_hood
