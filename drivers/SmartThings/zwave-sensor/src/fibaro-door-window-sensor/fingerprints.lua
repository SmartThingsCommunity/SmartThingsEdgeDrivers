-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local FIBARO_DOOR_WINDOW_SENSOR_FINGERPRINTS = {
  { manufacturerId = 0x010F, prod = 0x0700, productId = 0x1000 }, -- Fibaro Open/Closed Sensor (FGK-10x) / Europe
  { manufacturerId = 0x010F, prod = 0x0700, productId = 0x2000 }, -- Fibaro Open/Closed Sensor (FGK-10x) / NA
  { manufacturerId = 0x010F, prod = 0x0702, productId = 0x1000 }, -- Fibaro Open/Closed Sensor 2 (FGDW-002) / Europe
  { manufacturerId = 0x010F, prod = 0x0702, productId = 0x2000 }, -- Fibaro Open/Closed Sensor 2 (FGDW-002) / NA
  { manufacturerId = 0x010F, prod = 0x0702, productId = 0x3000 }, -- Fibaro Open/Closed Sensor 2 (FGDW-002) / ANZ
  { manufacturerId = 0x010F, prod = 0x0701, productId = 0x2001 }, -- Fibaro Open/Closed Sensor with temperature (FGK-10X) / NA
  { manufacturerId = 0x010F, prod = 0x0701, productId = 0x1001 }, -- Fibaro Open/Closed Sensor
  { manufacturerId = 0x010F, prod = 0x0501, productId = 0x1002 }  -- Fibaro Open/Closed Sensor
}

return FIBARO_DOOR_WINDOW_SENSOR_FINGERPRINTS
