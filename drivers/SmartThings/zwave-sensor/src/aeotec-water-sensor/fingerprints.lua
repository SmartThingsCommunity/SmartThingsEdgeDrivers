-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local ZWAVE_WATER_TEMP_HUMIDITY_FINGERPRINTS = {
  { manufacturerId = 0x0371, productType = 0x0002, productId = 0x0013 }, -- Aeotec Water Sensor 7 Pro EU
  { manufacturerId = 0x0371, productType = 0x0102, productId = 0x0013 }, -- Aeotec Water Sensor 7 Pro US
  { manufacturerId = 0x0371, productType = 0x0202, productId = 0x0013 }, -- Aeotec Water Sensor 7 Pro AU
  { manufacturerId = 0x0371, productId = 0x0012 } -- Aeotec Water Sensor 7
}

return ZWAVE_WATER_TEMP_HUMIDITY_FINGERPRINTS
