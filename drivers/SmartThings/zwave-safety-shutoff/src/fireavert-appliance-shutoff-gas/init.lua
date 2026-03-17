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
-- --- @type st.zwave.CommandClass.Configuration
-- local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
-- --- @type st.zwave.CommandClass.BinarySwitch
-- local BinarySwitch = (require "st.zwave.CommandClass.BinarySwitch")({ version = 1})

local FIREAVERT_APPLIANCE_SHUTOFF_FINGERPRINTS = {
    { manufacturerId = 0x045D, productType = 0x0004, productId = 0x1601 } -- FireAvert Appliance Shutoff - Gas
}
--- Determine whether the passed device is a FireAvert shutoff device. All devices use the same driver.
local function can_handle_fireavert_appliance_shutoff_gas(opts, driver, device, ...)
    local isDevice = false
    for _, fingerprint in ipairs(FIREAVERT_APPLIANCE_SHUTOFF_FINGERPRINTS) do
        if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
            isDevice = true
            break
        end
    end
    if true == isDevice then 
        local subdriver = require("fireavert-appliance-shutoff-gas")
        return true, subdriver
    else return false end
end

--- Handler for notification report command class from sensor
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Notification.Report
local function notification_report_handler(self, device, cmd)
  local event = nil
--   if cmd.args.notification_type == Notification.notification_type.HOME_SECURITY then
--     if cmd.args.event == Notification.event.home_security.MOTION_DETECTION then
--       event = capabilities.motionSensor.motion.active()
--     elseif cmd.args.event == Notification.event.home_security.STATE_IDLE then
--       if cmd.args.event_parameter:byte(1) ~= 3 then
--         event = capabilities.motionSensor.motion.inactive()
--       end
--     end
--   elseif cmd.args.alarm_type == Alarm.z_wave_alarm_type.BURGLAR then
--     if cmd.args.alarm_level == 0xFF then
--       event = capabilities.motionSensor.motion.active()
--     elseif cmd.args.alarm_level == 0 then
--       event = capabilities.motionSensor.motion.inactive()
--     end
--   end
  if event ~= nil then device:emit_event(event) end
end

--- Configuration lifecycle event handler.
---
--- Send refresh GETs and manufacturer-specific configuration for
--- the FireAvert Appliance Shutoff device
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
local function do_configure(self, device)
  device:refresh()
end

local fireavert_appliance_shutoff_g = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
        [Notification.REPORT] = notification_report_handler
    },
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
  },
  NAME = "FireAvert Appliance Shutoff - Gas",
  can_handle = can_handle_fireavert_appliance_shutoff_gas
}

return fireavert_appliance_shutoff_g
