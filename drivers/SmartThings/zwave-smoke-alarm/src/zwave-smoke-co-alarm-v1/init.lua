-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Alarm
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 1 })

-- Devices that use this DTH:
--   manufacturerId = 0x0138, productType = 0x0001, productId = 0x0001 -- First Alert Smoke Detector
--   manufacturerId = 0x0138, productType = 0x0001, productId = 0x0002 -- First Alert Smoke & CO Detector
--   manufacturerId = 0x0138, productType = 0x0001, productId = 0x0003 -- First Alert Smoke & CO Detector

--- Determine whether the passed device only supports V1 or V2 of the Alarm command class
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @return boolean true if the device is smoke co alarm
  NAME = "Z-Wave smoke and CO alarm V1",
  can_handle = require("zwave-smoke-co-alarm-v1.can_handle"),
}

return zwave_alarm
