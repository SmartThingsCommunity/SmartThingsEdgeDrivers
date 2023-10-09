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

local UserCode = (require "st.zwave.CommandClass.UserCode")({version=1})
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })

local YALE_MFR = 0x0129

local function can_handle_yale_lock(opts, self, device, cmd, ...)
  if device.zwave_manufacturer_id == YALE_MFR then
    local subdriver = require("yale-lock")
    return true, subdriver
  end
  return false
end

local function update_preferences(driver, device, args)
  device.log.info_with({ hub_logs = true }, "Updated preferences for zwave yale lock test driver")
end

local function do_configure(driver, device)
  device.log.info_with({ hub_logs = true }, "Do configure for zwave yale lock test driver")
  device:set_update_preferences_fn(update_preferences)
end

local function wakeup_notification(driver, device, cmd)
  device.log.info_with({ hub_logs = true }, "Wakeup notification for zwave yale lock test driver")
  device:refresh()
end

local schlage_lock = {
  zwave_handlers = {
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
  },
  NAME = "Yale Lock Test Driver",
  can_handle = can_handle_yale_lock,
}

return schlage_lock
