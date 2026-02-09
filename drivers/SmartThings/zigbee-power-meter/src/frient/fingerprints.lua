-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local ZIGBEE_POWER_METER_FINGERPRINTS = {
  { model = "ZHEMI101", preferences = true, },
  { model = "EMIZB-132", preferences = false, },
  { model = "EMIZB-141", preferences = true, MIN_BAT = 2.3 , MAX_BAT = 3.0 },
  { model = "EMIZB-151", preferences = false, }
}

return ZIGBEE_POWER_METER_FINGERPRINTS
