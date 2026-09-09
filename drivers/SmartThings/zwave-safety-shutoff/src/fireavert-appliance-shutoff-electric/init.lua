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
--- @type st.zwave.CommandClass.ApplicationStatus
local ApplicationStatus = (require "st.zwave.CommandClass.ApplicationStatus")({ version = 1 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })

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

--- Only ever fires when the device attempts to turn the switch back on and this is rejected.
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.ApplicationStatus.ApplicationRejectedRequest
local function app_rejected_handler(driver, device, cmd)
  print("Application rejected received from device, unable to rearm")
  --- Reset the UI switch to match the current relay state.
  device:emit_event(capabilities.switch.switch.off({state_change = true}))
end


--- Handle a Switch OFF command from the application.
--- 
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param command ST level capability command
local function st_switch_off_handler(driver, device, command)
  device:send(SwitchBinary:Set({
      target_value = SwitchBinary.value.OFF_DISABLE,
      duration = 0
    })
  )
  device:send(SwitchBinary:Get({}))
end

--- Handle a Switch ON command from the application.
--- Switching on is not allowed in some cases, so that is handled through the ApplicationRejected
--- handler.
--- 
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param command ST level capability command
local function st_switch_on_handler(driver, device, command)
  device:send(SwitchBinary:Set({
      target_value = SwitchBinary.value.ON_ENABLE,
      duration = 0
    })
  )
  device:send(SwitchBinary:Get({}))
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
    [cc.APPLICATION_STATUS] = {
      [ApplicationStatus.APPLICATION_REJECTED_REQUEST] = app_rejected_handler,
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.off.NAME] = st_switch_off_handler,
      [capabilities.switch.commands.on.NAME] = st_switch_on_handler
    },
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
  },
  NAME = "FireAvert Appliance Shutoff - Electric",
  can_handle = can_handle_fireavert_appliance_shutoff_e
}

return fireavert_appliance_shutoff_e
