-- Copyright 2025 SmartThings
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
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version=1 })
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({version=1})

local AEOTEC_SMOKE_SHIELD_FINGERPRINTS = {
    { manufacturerId = 0x0371, productType = 0x0002 , productId = 0x0032 }
}

--- Determine whether the passed device is aeotec smoke shield
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @return boolean true if the device is aeotec smoke shield
local function can_handle_aeotec_smoke_shield(opts, driver, device, cmd, ...)
  for _, fingerprint in ipairs(AEOTEC_SMOKE_SHIELD_FINGERPRINTS) do
    if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function device_added(self, device)
  device:emit_event(capabilities.smokeDetector.smoke.clear())
  device:emit_event(capabilities.tamperAlert.tamper.clear())
  device:send(Battery:Get({}))
end

local function wakeup_notification_handler(self, device, cmd)
  --Note sending WakeUpIntervalGet the first time a device wakes up will happen by default in Lua libs 0.49.x and higher
  --This is done to help the hub correctly set the checkInterval for migrated devices.
  if not device:get_field("__wakeup_interval_get_sent") then
    device:send(WakeUp:IntervalGetV1({}))
    device:set_field("__wakeup_interval_get_sent", true)
  end
  device:emit_event(capabilities.smokeDetector.smoke.clear())
  device:send(Battery:Get({}))
end

local aeotec_smoke_shield = {
  zwave_handlers = {
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification_handler
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  NAME = "Aeotec SmokeShield",
  can_handle = can_handle_aeotec_smoke_shield,
  health_check = false,
}

return aeotec_smoke_shield
