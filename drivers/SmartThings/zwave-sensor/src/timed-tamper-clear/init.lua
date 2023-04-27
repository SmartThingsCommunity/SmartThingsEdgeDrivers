-- Copyright 2023 SmartThings
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

--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 4 })
local capabilities = require "st.capabilities"

local TAMPER_TIMER = "_tamper_timer"
local TAMPER_CLEAR = 10
local FIBARO_DOOR_WINDOW_MFR_ID = 0x010F

local function can_handle_tamper_event(opts, driver, device, cmd, ...)
  return device.zwave_manufacturer_id ~= FIBARO_DOOR_WINDOW_MFR_ID and
    opts.dispatcher_class == "ZwaveDispatcher" and
    cmd ~= nil and
    cmd.cmd_class ~= nil and
    cmd.cmd_class == cc.NOTIFICATION and
    cmd.cmd_id == Notification.REPORT and
    cmd.args.notification_type == Notification.notification_type.HOME_SECURITY and
    (cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED or
    cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_MOVED)
end

-- This behavior is from zwave-door-window-sensor.groovy. We've seen this behavior
-- in Ecolink and several other z-wave sensors that do not send tamper clear events
local function handle_tamper_event(driver, device, cmd)
  device:emit_event_for_endpoint(cmd.src_channel, capabilities.tamperAlert.tamper.detected())
  -- device doesn't report all clear
  local tamper_timer = device:get_field(TAMPER_TIMER)
  if tamper_timer ~= nil then
    device.thread:cancel_timer(tamper_timer)
  end
  device:set_field(TAMPER_TIMER, device.thread:call_with_delay(TAMPER_CLEAR, function()
    device:emit_event_for_endpoint(cmd.src_channel, capabilities.tamperAlert.tamper.clear())
    device:set_field(TAMPER_TIMER, nil)
  end))
end

local timed_tamper_clear = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = handle_tamper_event
    }
  },
  NAME = "timed tamper clear",
  can_handle = can_handle_tamper_event
}

return timed_tamper_clear
