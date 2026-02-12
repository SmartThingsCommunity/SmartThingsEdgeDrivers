-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Determine whether the passed device is zwave-plus-motion-temp-sensor
local function can_handle_vision_motion_detector(opts, driver, device, ...)
  local VISION_MOTION_DETECTOR_FINGERPRINTS = { manufacturerId = 0x0109, productType = 0x2002, productId = 0x0205 } -- Vision Motion Detector ZP3102
  if device:id_match(
    VISION_MOTION_DETECTOR_FINGERPRINTS.manufacturerId,
    VISION_MOTION_DETECTOR_FINGERPRINTS.productType,
    VISION_MOTION_DETECTOR_FINGERPRINTS.productId
  ) then
    return true, require("vision-motion-detector")
  end
  return false
end

return can_handle_vision_motion_detector
