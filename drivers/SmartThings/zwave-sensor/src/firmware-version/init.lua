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
--- @type st.zwave.CommandClass.Version
local Version = (require "st.zwave.CommandClass.Version")({ version = 1 })
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })

--This sub_driver will populate the currentVersion (firmware) when the firmwareUpdate capability is enabled
local FINGERPRINTS = {
  { manufacturerId = 0x027A, productType = 0x7000, productId = 0xE002 } -- Zooz ZSE42 Water Sensor
}

local function can_handle_fw(opts, driver, device, ...)
  if device:supports_capability_by_id(capabilities.firmwareUpdate.ID) then
    for _, fingerprint in ipairs(FINGERPRINTS) do
      if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
        local subDriver = require("firmware-version")
        return true, subDriver
      end
    end
  end
  return false
end

--Runs upstream handlers (ex zwave_handlers)
local function call_parent_handler(handlers, self, device, event, args)
  for _, func in ipairs(handlers or {}) do
    func(self, device, event, args)
  end
end

--Request version if not populated yet
local function send_version_get(driver, device)
  if device:get_latest_state("main", capabilities.firmwareUpdate.ID, capabilities.firmwareUpdate.currentVersion.NAME) == nil then
    device:send(Version:Get({}))
  end
end

local function version_report(driver, device, cmd)
  local major = cmd.args.application_version
  local minor = cmd.args.application_sub_version
  local fmtFirmwareVersion = string.format("%d.%02d", major, minor)
  device:emit_event(capabilities.firmwareUpdate.currentVersion({ value = fmtFirmwareVersion }))
end

local function wakeup_notification(driver, device, cmd)
  send_version_get(driver, device)
  --Call parent WakeUp functions
  call_parent_handler(driver.zwave_handlers[cc.WAKE_UP][WakeUp.NOTIFICATION], driver, device, cmd)
end

local function device_init(driver, device)
  --Call main init function
  driver.lifecycle_handlers.init(driver, device)
  --Extras for this sub_driver
  send_version_get(driver, device)
end

local firmware_version = {
  NAME = "firmware_version",
  can_handle = can_handle_fw,

  lifecycle_handlers = {
    init = device_init,
  },
  zwave_handlers = {
    [cc.VERSION] = {
      [Version.REPORT] = version_report
    },
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification
    }
  }
}

return firmware_version