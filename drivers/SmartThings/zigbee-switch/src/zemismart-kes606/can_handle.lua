-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local device_lib = require "st.device"

return function(_, _, device)
  if device == nil then return false end
  local parent = device
  if device.network_type == device_lib.NETWORK_TYPE_CHILD then
    local gang = tonumber((device.parent_assigned_child_key or ""):match("^gang([1-4])$"))
    if gang == nil then return false end
    parent = device:get_parent_device()
  elseif device.network_type ~= device_lib.NETWORK_TYPE_ZIGBEE then
    return false
  end
  if parent ~= nil and parent:get_manufacturer() == "_TZ3000_hurauima"
      and parent:get_model() == "TS0726" then
    return true, require("zemismart-kes606")
  end
  return false
end
