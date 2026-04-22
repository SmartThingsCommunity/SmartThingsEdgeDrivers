-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local ZWAVE_FIBARO_KEYFOB_FINGERPRINTS = {
  {mfr = 0x010F, prod = 0x1001, model = 0x1000}, -- Fibaro KeyFob EU
  {mfr = 0x010F, prod = 0x1001, model = 0x2000}, -- Fibaro KeyFob US
  {mfr = 0x010F, prod = 0x1001, model = 0x3000} -- Fibaro KeyFob AU
}

return ZWAVE_FIBARO_KEYFOB_FINGERPRINTS
