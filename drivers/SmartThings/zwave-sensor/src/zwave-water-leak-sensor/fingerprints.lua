-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local WATER_LEAK_SENSOR_FINGERPRINTS = {
  {mfr = 0x0084, prod = 0x0063, model = 0x010C},  -- SmartThings Water Leak Sensor
  {mfr = 0x0084, prod = 0x0053, model = 0x0216},  -- FortrezZ Water Leak Sensor
  {mfr = 0x021F, prod = 0x0003, model = 0x0085},  -- Dome Leak Sensor
  {mfr = 0x0258, prod = 0x0003, model = 0x0085},  -- NEO Coolcam Water Sensor
  {mfr = 0x0258, prod = 0x0003, model = 0x1085},  -- NEO Coolcam Water Sensor
  {mfr = 0x0258, prod = 0x0003, model = 0x2085},  -- NEO Coolcam Water Sensor
  {mfr = 0x0086, prod = 0x0002, model = 0x007A},  -- Aeotec Water Sensor 6 (EU)
  {mfr = 0x0086, prod = 0x0102, model = 0x007A},  -- Aeotec Water Sensor 6 (US)
  {mfr = 0x0086, prod = 0x0202, model = 0x007A},  -- Aeotec Water Sensor 6 (AU)
  {mfr = 0x000C, prod = 0x0201, model = 0x000A},  -- HomeSeer LS100+ Water Sensor
  {mfr = 0x0173, prod = 0x4C47, model = 0x4C44},  -- Leak Gopher Z-Wave Leak Detector
  {mfr = 0x027A, prod = 0x7000, model = 0xE002}   -- Zooz ZSE42 XS Water Leak Sensor
}

return WATER_LEAK_SENSOR_FINGERPRINTS
