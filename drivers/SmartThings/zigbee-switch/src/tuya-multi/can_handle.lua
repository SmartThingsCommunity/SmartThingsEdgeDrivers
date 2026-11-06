-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local device_lib = require "st.device"

local function is_multi_endpoint(device)
  local main_endpoint = device:get_endpoint(0x0006)
  for _, ep in ipairs(device.zigbee_endpoints) do
    if ep.id ~= main_endpoint then
      return true
    end
  end
  return false
end

return function(opts, driver, device)
  if require("tuya-multi.zemismart-kes606.can_handle")(opts, driver, device) then
    return true, require("tuya-multi")
  end
  if device.network_type == device_lib.NETWORK_TYPE_CHILD then return false end

  local TUYA_MFR_HEADER = "_TZ"
  local manufacturer = device:get_manufacturer()
  if manufacturer ~= nil and string.sub(manufacturer,1,3) == TUYA_MFR_HEADER and is_multi_endpoint(device) then  -- if it is a tuya device, then send the magic packet
      local subdriver = require("tuya-multi")
      return true, subdriver
  end
  return false
end
