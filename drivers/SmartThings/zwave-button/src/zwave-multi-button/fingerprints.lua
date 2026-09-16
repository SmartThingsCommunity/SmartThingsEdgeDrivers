-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local ZWAVE_MULTI_BUTTON_FINGERPRINTS = {
  {mfr = 0x010F, prod = 0x1001, model = 0x1000}, -- Fibaro KeyFob EU
  {mfr = 0x010F, prod = 0x1001, model = 0x2000}, -- Fibaro KeyFob US
  {mfr = 0x010F, prod = 0x1001, model = 0x3000}, -- Fibaro KeyFob AU
  {mfr = 0x0371, prod = 0x0002, model = 0x0003}, -- Aeotec NanoMote Quad EU
  {mfr = 0x0371, prod = 0x0102, model = 0x0003}, -- Aeotec NanoMote Quad US
  {mfr = 0x0086, prod = 0x0001, model = 0x0058}, -- Aeotec KeyFob EU
  {mfr = 0x0086, prod = 0x0101, model = 0x0058}, -- Aeotec KeyFob US
  {mfr = 0x0086, prod = 0x0002, model = 0x0082}, -- Aeotec Wallmote Quad EU
  {mfr = 0x0086, prod = 0x0102, model = 0x0082}, -- Aeotec Wallmote Quad US
  {mfr = 0x0086, prod = 0x0002, model = 0x0081}, -- Aeotec Wallmote EU
  {mfr = 0x0086, prod = 0x0102, model = 0x0081}, -- Aeotec Wallmote US
  {mfr = 0x0060, prod = 0x000A, model = 0x0003}, -- Everspring Remote Control
  {mfr = 0x0086, prod = 0x0001, model = 0x0003}, -- Aeotec Mimimote,
  {mfr = 0x0371, prod = 0x0102, model = 0x0016}, -- Aeotec illumino Wallmote 7,
  {mfr = 0x0460, prod = 0x0009, model = 0x0081}, -- Shelly Wave i4,
  {mfr = 0x0460, prod = 0x0009, model = 0x0082}  -- Shelly Wave i4DC,
}

return ZWAVE_MULTI_BUTTON_FINGERPRINTS
