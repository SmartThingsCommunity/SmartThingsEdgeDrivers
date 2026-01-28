-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local ZIGBEE_POWER_METER_FINGERPRINTS = {
  { model = "ZHEMI101", preferences = true, battery = false },
  { model = "EMIZB-132", preferences = false, battery = false },
  { model = "EMIZB-141", preferences = true, battery = true, MIN_BAT = 2.3 , MAX_BAT = 3.0 }
}

return ZIGBEE_POWER_METER_FINGERPRINTS
