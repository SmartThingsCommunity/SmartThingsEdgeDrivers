-- Copyright 2022 SmartThings, Inc.
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

--- Default handler for alarm command class reports
---
--- This converts alarm V1 reports to correct smoke events
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Alarm.Report
local function alarm_report_handler(self, device, cmd)
  if cmd.args.alarm_type == Alarm.z_wave_alarm_type.SMOKE then
    if cmd.args.alarm_level == 0 then
      device:emit_event(capabilities.smokeDetector.smoke.clear())
    else
      device:emit_event(capabilities.smokeDetector.smoke.detected())
    end
  elseif cmd.args.alarm_type == Alarm.z_wave_alarm_type.CO then
    if cmd.args.alarm_level == 0 then
      device:emit_event(capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
    else
      device:emit_event(capabilities.carbonMonoxideDetector.carbonMonoxide.detected())
    end
  elseif cmd.args.alarm_type == 12 then -- undocumented value
    if cmd.args.alarm_level == 0 then
      device:emit_event(capabilities.smokeDetector.smoke.clear())
      device:emit_event(capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
    else
      device:emit_event(capabilities.smokeDetector.smoke.tested())
      device:emit_event(capabilities.carbonMonoxideDetector.carbonMonoxide.tested())
    end
  elseif cmd.args.alarm_type == 13 then -- undocumented value
    device:emit_event(capabilities.smokeDetector.smoke.clear())
  end
end

local zwave_alarm = {
  zwave_handlers = {
    [cc.ALARM] = {
      -- also shall handle cc.ALARM
      [Alarm.REPORT] = alarm_report_handler
    }
  },
  NAME = "Z-Wave smoke and CO alarm V1",
  can_handle = require("zwave-smoke-co-alarm-v1.can_handle"),
}

return zwave_alarm
