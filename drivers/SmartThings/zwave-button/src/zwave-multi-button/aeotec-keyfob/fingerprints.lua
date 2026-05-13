-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local ZWAVE_AEOTEC_KEYFOB_FINGERPRINTS = {
  {mfr = 0x0086, prod = 0x0101, model = 0x0058}, -- Aeotec KeyFob US
  {mfr = 0x0086, prod = 0x0001, model = 0x0058}, -- Aeotec KeyFob EU
  {mfr = 0x0086, prod = 0x0001, model = 0x0026} -- Aeotec Panic Button
}

return ZWAVE_AEOTEC_KEYFOB_FINGERPRINTS
