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
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
--- @type st.zwave.CommandClass.Battery
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})

local MULTIFUNCTIONAL_SIREN_FINGERPRINTS = {
  { manufacturerId = 0x027A, productType = 0x000C, productId = 0x0003 }, -- Zooz S2 Multisiren ZSE19
  { manufacturerId = 0x0060, productType = 0x000C, productId = 0x0003 } -- Everspring Indoor Voice Siren
}

--- Determine whether the passed device is multifunctional siren
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_multifunctional_siren(opts, driver, device, ...)
  for _, fingerprint in ipairs(MULTIFUNCTIONAL_SIREN_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local zwave_handlers = {}

--- Default handler for notification command class reports
---
--- This converts tamper reports across tamper alert types into tamper events.
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Notification.Report
local function notification_handler(self, device, cmd)
  local event
  if (cmd.args.notification_type == Notification.notification_type.HOME_SECURITY) then
    if cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED then
      event = capabilities.tamperAlert.tamper.detected()
    else
      event = capabilities.tamperAlert.tamper.clear()
    end
  end
  device:emit_event(event)
end

local do_configure = function(self, device)
  device:refresh()
  device:send(Notification:Get({notification_type = Notification.notification_type.HOME_SECURITY}))
  device:send(Basic:Get({}))
end

local capability_handlers = {}

local multifunctional_siren = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_handler
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  NAME = "multifunctional siren",
  can_handle = can_handle_multifunctional_siren,
}

return multifunctional_siren
