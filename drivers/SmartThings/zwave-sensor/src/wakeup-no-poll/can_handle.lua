-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle(opts, driver, device, ...)
  local fingerprint = {manufacturerId = 0x014F, productType = 0x2001, productId = 0x0102} -- NorTek open/close sensor
  if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
    return true, require("wakeup-no-poll")
  end
  return false
end

return can_handle
