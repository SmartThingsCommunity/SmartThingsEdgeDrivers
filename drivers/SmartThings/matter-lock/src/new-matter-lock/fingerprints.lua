-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local NEW_MATTER_LOCK_PRODUCTS = {
  {0x115f, 0x2802}, -- AQARA, U200
  {0x115f, 0x2801}, -- AQARA, U300
  {0x115f, 0x2807}, -- AQARA, U200 Lite
  {0x115f, 0x2804}, -- AQARA, U400
  {0x115f, 0x286A}, -- AQARA, U200 US
  {0x147F, 0x0001}, -- U-tec
  {0x147F, 0x0008}, -- Ultraloq, Bolt Smart Matter Door Lock
  {0x144F, 0x4002}, -- Yale, Linus Smart Lock L2
  {0x101D, 0x8110}, -- Yale, New Lock
  {0x1533, 0x0001}, -- eufy, E31
  {0x1533, 0x0002}, -- eufy, E30
  {0x1533, 0x0003}, -- eufy, C34
  {0x1533, 0x000F}, -- eufy, FamiLock S3 Max
  {0x1533, 0x0010}, -- eufy, FamiLock S3
  {0x1533, 0x0011}, -- eufy, FamiLock E34
  {0x1533, 0x0012}, -- eufy, FamiLock E35
  {0x1533, 0x0016}, -- eufy, FamiLock E32
  {0x1533, 0x0014}, -- eufy, FamiLock E40
  {0x135D, 0x00B1}, -- Nuki, Smart Lock Pro
  {0x135D, 0x00B2}, -- Nuki, Smart Lock
  {0x135D, 0x00C1}, -- Nuki, Smart Lock
  {0x135D, 0x00A1}, -- Nuki, Smart Lock
  {0x135D, 0x00B0}, -- Nuki, Smart Lock
  {0x15F2, 0x0001}, -- Viomi, AiSafety Smart Lock E100
  {0x158B, 0x0001}, -- Deasino, DS-MT01
  {0x10E1, 0x2002}, -- VDA
  {0x1421, 0x0042}, -- Kwikset Halo Select Plus
  {0x1421, 0x0081}, -- Kwikset Aura Reach
  {0x1236, 0xa538}, -- Schlage Sense Pro
}

return NEW_MATTER_LOCK_PRODUCTS
