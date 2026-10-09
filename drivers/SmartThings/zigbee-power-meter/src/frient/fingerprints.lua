-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local ZIGBEE_POWER_METER_FINGERPRINTS = {
  { model = "ZHEMI101", },
  { model = "EMIZB-132", },
  { model = "EMIZB-141", MIN_BAT = 2.3 , MAX_BAT = 3.0 },
  { model = "EMIZB-151", }
}

return ZIGBEE_POWER_METER_FINGERPRINTS
