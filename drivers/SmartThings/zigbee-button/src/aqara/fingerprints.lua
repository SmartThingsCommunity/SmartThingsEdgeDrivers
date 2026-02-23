-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local FINGERPRINTS = {
  ["lumi.remote.b1acn02"] = { mfr = "LUMI", btn_cnt = 1, type = "CR2032", quantity = 1 },   -- Aqara Wireless Mini Switch T1
  ["lumi.remote.acn003"] = { mfr = "LUMI", btn_cnt = 1, type = "CR2032", quantity = 1 },    -- Aqara Wireless Remote Switch E1 (Single Rocker)
  ["lumi.remote.b186acn03"] = { mfr = "LUMI", btn_cnt = 1, type = "CR2032", quantity = 1 }, -- Aqara Wireless Remote Switch T1 (Single Rocker)
  ["lumi.remote.b286acn03"] = { mfr = "LUMI", btn_cnt = 3, type = "CR2032", quantity = 1 }, -- Aqara Wireless Remote Switch T1 (Double Rocker)
  ["lumi.remote.b18ac1"] = { mfr = "LUMI", btn_cnt = 1, type = "CR2450", quantity = 1 },    -- Aqara Wireless Remote Switch H1 (Single Rocker)
  ["lumi.remote.b28ac1"] = { mfr = "LUMI", btn_cnt = 3, type = "CR2450", quantity = 1 }     -- Aqara Wireless Remote Switch H1 (Double Rocker)
}

return FINGERPRINTS
