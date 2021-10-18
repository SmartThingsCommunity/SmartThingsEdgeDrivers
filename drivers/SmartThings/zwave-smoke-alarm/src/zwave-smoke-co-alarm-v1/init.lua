-- Copyright 2021 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Alarm
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 1 })

local SMOKE_CO_ALARM_FINGERPRINTS = {
  { manufacturerId = 0x0138, productType = 0x0001, productId = 0x0002 }, -- First Alert Smoke Detector
}

--- Determine whether the passed device is Smoke Alarm
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @return boolean true if the device is smoke co alarm
local function can_handle_v1_alarm(opts, driver, device, cmd, ...)
  if cmd.version == 1 then
  -- we only handle v1 reports; this is Notification V3 ( or higher) command
    for _, fingerprint in ipairs(SMOKE_CO_ALARM_FINGERPRINTS) do
      if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
        return true
      end
    end
  end
  return false
end

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
    device:emit_event(capabilities.smokeDetector.smoke.tested())
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
  can_handle = can_handle_v1_alarm,
}

return zwave_alarm
