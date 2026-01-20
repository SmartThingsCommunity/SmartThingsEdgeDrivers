-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local AEOTEC_NANO_SHUTTER_FINGERPRINTS = {
  {mfr = 0x0086, prod = 0x0003, model = 0x008D}, -- Aeotec nano shutter EU
  {mfr = 0x0086, prod = 0x0103, model = 0x008D}, -- Aeotec nano shutter US
  {mfr = 0x0371, prod = 0x0003, model = 0x008D}, -- Aeotec nano shutter EU
  {mfr = 0x0371, prod = 0x0103, model = 0x008D} -- Aeotec nano shutter US
}

return AEOTEC_NANO_SHUTTER_FINGERPRINTS
