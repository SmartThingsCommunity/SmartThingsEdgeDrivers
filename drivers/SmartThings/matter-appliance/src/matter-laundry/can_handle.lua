-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function is_matter_laundry_device(opts, driver, device)
  local LAUNDRY_WASHER_DEVICE_TYPE_ID = 0x0073
  local LAUNDRY_DRYER_DEVICE_TYPE_ID = 0x007C
  local LAUNDRY_DEVICE_TYPE_ID= "__laundry_device_type_id"
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == LAUNDRY_WASHER_DEVICE_TYPE_ID or dt.device_type_id == LAUNDRY_DRYER_DEVICE_TYPE_ID then
        device:set_field(LAUNDRY_DEVICE_TYPE_ID, dt.device_type_id, {persist = true})
        return dt.device_type_id, require("matter-laundry")
      end
    end
  end
  return false
end

return is_matter_laundry_device
