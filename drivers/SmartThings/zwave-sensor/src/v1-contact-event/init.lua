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

local function can_handle_v1_contact_event(opts, driver, device, cmd, ...)
  return opts.dispatcher_class == "ZwaveDispatcher" and
    cmd ~= nil and
    cmd.cmd_class ~= nil and
    cmd.cmd_class == cc.NOTIFICATION and
    cmd.cmd_id == Notification.REPORT and
    cmd.args.notification_type == Notification.notification_type.HOME_SECURITY and
    cmd.args.v1_alarm_type == 0x07
end

-- This behavior is from zwave-door-window-sensor.groovy, where it is
-- indicated that certain monoprice sensors had this behavior. Also,
-- we have reports of Nortek sensors behaving the same way.
local function handle_v1_contact_event(driver, device, cmd)
  if cmd.args.event == 0x02 or cmd.args.event == 0xFE then
    if cmd.args.v1_alarm_level == 0 then
      device:emit_event_for_endpoint(cmd.src_channel, capabilities.contactSensor.contact.closed())
    else
      device:emit_event_for_endpoint(cmd.src_channel, capabilities.contactSensor.contact.open())
    end
  end
end

local v1_contact_event = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = handle_v1_contact_event
    }
  },
  NAME = "v1 contact event",
  can_handle = can_handle_v1_contact_event
}

return v1_contact_event
