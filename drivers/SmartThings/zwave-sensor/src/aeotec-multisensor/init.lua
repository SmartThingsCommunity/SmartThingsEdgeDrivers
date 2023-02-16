-- Copyright 2022 SmartThings
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
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })

local TIMER = "timed_clear"
local TAMPER_CLEAR_TIME = 10

local AEOTEC_MULTISENSOR_FINGERPRINTS = {
  { manufacturerId = 0x0086, productId = 0x0064 }, -- MultiSensor 6
  { manufacturerId = 0x0371, productId = 0x0018 }, -- MultiSensor 7
}

local function can_handle_aeotec_multisensor(opts, self, device, ...)
  for _, fingerprint in ipairs(AEOTEC_MULTISENSOR_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function notification_report_handler(self, device, cmd)
  local event
  if cmd.args.notification_type == Notification.notification_type.POWER_MANAGEMENT then
    if cmd.args.event == Notification.event.power_management.AC_MAINS_DISCONNECTED then
      event = capabilities.powerSource.powerSource.battery()
    elseif cmd.args.event == Notification.event.power_management.AC_MAINS_RE_CONNECTED then
      event = capabilities.powerSource.powerSource.dc()
    end
  elseif cmd.args.notification_type == Notification.notification_type.HOME_SECURITY then
    if cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED or
      cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_MOVED then
      event = capabilities.tamperAlert.tamper.detected()
      local timer = device:get_field(TIMER)
      if timer ~= nil then --received a new event before the clear fired
        device.thread:cancel_timer(timer)
      end
      timer = device.thread:call_with_delay(TAMPER_CLEAR_TIME, function(d)
        device:emit_event(capabilities.tamperAlert.tamper.clear())
        device:set_field(TIMER, nil)
      end)
      device:set_field(TIMER, timer)
    elseif cmd.args.event == Notification.event.home_security.STATE_IDLE then
      device:emit_event(capabilities.motionSensor.motion.inactive())
      event = capabilities.tamperAlert.tamper.clear()
    elseif cmd.args.event == Notification.event.home_security.MOTION_DETECTION then
      event = capabilities.motionSensor.motion.active()
    end
  end

  if event ~= nil then
    device:emit_event(event)
  end
end

local aeotec_multisensor = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    }
  },
  sub_drivers = {
    require("aeotec-multisensor/multisensor-6"),
    require("aeotec-multisensor/multisensor-7")
  },
  NAME = "aeotec multisensor",
  can_handle = can_handle_aeotec_multisensor
}

return aeotec_multisensor
