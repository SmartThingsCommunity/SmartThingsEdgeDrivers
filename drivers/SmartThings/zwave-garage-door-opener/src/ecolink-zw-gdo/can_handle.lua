-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_ecolink_garage_door(opts, driver, device, ...)
  return device:id_match(ECOLINK_GARAGE_DOOR_FINGERPRINTS.manufacturerId,
                          ECOLINK_GARAGE_DOOR_FINGERPRINTS.productType,
                          ECOLINK_GARAGE_DOOR_FINGERPRINTS.productId)
end

return can_handle_ecolink_garage_door
