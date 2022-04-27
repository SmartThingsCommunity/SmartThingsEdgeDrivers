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
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.CommandClass.DoorLock
local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })

local SCAN_CODES_CHECK_INTERVAL = 30

local function periodic_codes_state_verification(driver, device)
  local scan_codes_state = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.scanCodes.NAME)
  if scan_codes_state == "Scanning" then
    driver:inject_capability_command(device,
            { capability = capabilities.lockCodes.ID,
              command = capabilities.lockCodes.commands.reloadAllCodes.NAME,
              args = {}
            }
    )
    device.thread:call_with_delay(
      SCAN_CODES_CHECK_INTERVAL,
      function(d)
        periodic_codes_state_verification(driver, device)
      end
    )
  end
end

--- Builds up initial state for the device
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
local function added_handler(self, device)
  if (device:supports_capability(capabilities.lockCodes)) then
    self:inject_capability_command(device,
            { capability = capabilities.lockCodes.ID,
              command = capabilities.lockCodes.commands.reloadAllCodes.NAME,
              args = {} })
    device.thread:call_with_delay(
      SCAN_CODES_CHECK_INTERVAL,
      function(d)
        periodic_codes_state_verification(self, device)
      end
    )
  end
  device:send(DoorLock:OperationGet({}))
  device:send(Battery:Get({}))
  if (device:supports_capability(capabilities.tamperAlert)) then
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  end
end

local driver_template = {
  supported_capabilities = {
    capabilities.lock,
    capabilities.lockCodes,
    capabilities.battery,
    capabilities.tamperAlert
  },
  lifecycle_handlers = {
    added = added_handler
  },
  sub_drivers = {
    require("zwave-alarm-v1-lock"),
    require("schlage-lock"),
    require("samsung-lock"),
    require("keywe-lock")
  }
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
local lock = ZwaveDriver("zwave_lock", driver_template)
lock:run()
