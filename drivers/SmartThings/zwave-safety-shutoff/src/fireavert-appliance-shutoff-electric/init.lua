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

--- This is a notification type that is not available in SmartThings but does exist in the Z-Wave Specification (2025B +).
local APPLIANCE_SAFETY_INTERLOCK_ENGAGED = 0x16

local FIREAVERT_APPLIANCE_SHUTOFF_FINGERPRINTS = {
    { manufacturerId = 0x045D, productType = 0x0004, productId = 0x0601 }, -- FireAvert Appliance Shutoff - 120V
    { manufacturerId = 0x045D, productType = 0x0004, productId = 0x0602 }, -- FireAvert Appliance Shutoff - 240V 3 Prong
    { manufacturerId = 0x045D, productType = 0x0004, productId = 0x0603 }, -- FireAvert Appliance Shutoff - 240V 4 Prong
}
--- Determine whether the passed device is a FireAvert shutoff device. All devices use the same driver.
local function can_handle_fireavert_appliance_shutoff_e(opts, driver, device, ...)
    local isDevice = false
    for _, fingerprint in ipairs(FIREAVERT_APPLIANCE_SHUTOFF_FINGERPRINTS) do
        if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
            isDevice = true
            break
        end
    end
    if true == isDevice then 
        local subdriver = require("fireavert-appliance-shutoff-electric")
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
  if cmd.args.notification_type == Notification.notification_type.SMOKE then
    if cmd.args.event == Notification.event.smoke.DETECTED then
      event = capabilities.soundDetection.soundDetected.fireAlarm()
    elseif cmd.args.event == Notification.event.smoke.STATE_IDLE then
      event = capabilities.soundDetection.soundDetected.noSound()
    end
  elseif cmd.args.notification_type == Notification.notification_type.APPLIANCE then
    if cmd.args.event == APPLIANCE_SAFETY_INTERLOCK_ENGAGED then
      -- event = capabilities.remoteControlStatus.remoteControlEnabled.false()
      print("Device cannot be remote controlled")
    else
      -- event = capabilities.remoteControlStatus.remoteControlEnabled.true()
      print("Device can be remote controlled")

    end

  end
  if event ~= nil then 
    print("notification event: %s", event)
    device:emit_event(event) 
    end
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

local fireavert_appliance_shutoff_e = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
        [Notification.REPORT] = notification_report_handler
    },
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
  },
  NAME = "FireAvert Appliance Shutoff - Electric",
  can_handle = can_handle_fireavert_appliance_shutoff_e
}

return fireavert_appliance_shutoff_e
