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
local cc = require "st.zwave.CommandClass"

local Association = (require "st.zwave.CommandClass.Association")({version=2})
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local access_control_event = Notification.event.access_control

local LockDefaults = require "st.zwave.defaults.lock"
local LockCodesDefaults = require "st.zwave.defaults.lockCodes"
local TamperDefaults = require "st.zwave.defaults.tamperAlert"

local KEYWE_MFR = 0x037B
local TAMPER_CLEAR_DELAY = 10

local function can_handle_keywe_lock(opts, self, device, cmd, ...)
  return device.zwave_manufacturer_id == KEYWE_MFR
end

local function clear_tamper_if_needed(device)
  local current_tamper_state = device:get_latest_state("main", capabilities.tamperAlert.ID, capabilities.tamperAlert.tamper.NAME)
  if current_tamper_state == "detected" then
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  end
end

local function notification_report_handler(self, device, cmd)
  local event
  if (cmd.args.notification_type == Notification.notification_type.ACCESS_CONTROL) then
    local event_code = cmd.args.event
    if event_code == access_control_event.WINDOW_DOOR_HANDLE_IS_OPEN then
      event = capabilities.lock.lock.unlocked()
    elseif event_code == access_control_event.WINDOW_DOOR_HANDLE_IS_CLOSED then
      event = capabilities.lock.lock.locked()
    end
    if event ~= nil then
      event["data"] = {method = "manual"}
    end
  end

  if event ~= nil then
    device:emit_event(event)
  else
    LockDefaults.zwave_handlers[cc.NOTIFICATION][Notification.REPORT](self, device, cmd)
    LockCodesDefaults.zwave_handlers[cc.NOTIFICATION][Notification.REPORT](self, device, cmd)
    TamperDefaults.zwave_handlers[cc.NOTIFICATION][Notification.REPORT](self, device, cmd)
    device.thread:call_with_delay(
      TAMPER_CLEAR_DELAY,
      function(d)
        clear_tamper_if_needed(device)
      end
    )
  end
end

local function do_configure(self, device)
  device:send(Association:Set({grouping_identifier = 2, node_ids = {self.environment_info.hub_zwave_id}}))
end

local keywe_lock = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  NAME = "Keywe Lock",
  can_handle = can_handle_keywe_lock,
}

return keywe_lock
