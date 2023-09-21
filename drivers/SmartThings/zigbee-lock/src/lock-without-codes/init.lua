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

local configurationMap = require "configurations"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local DoorLock = clusters.DoorLock
local PowerConfiguration = clusters.PowerConfiguration

local LOCK_WITHOUT_CODES_FINGERPRINTS = {
  { model = "E261-KR0B0Z0-HA" },
  { mfr = "Danalock", model = "V3-BTZB" }
}

local function can_handle_lock_without_codes(opts, driver, device)
  for _, fingerprint in ipairs(LOCK_WITHOUT_CODES_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function device_init(driver, device)
  local configuration = configurationMap.get_device_configuration(device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end
end

local function handle_lock(driver, device, cmd)
  device:send(DoorLock.commands.LockDoor(device))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local function handle_unlock(driver, device, cmd)
  device:send(DoorLock.commands.UnlockDoor(device))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local function do_refresh(driver, device)
  device:refresh()
end

local function do_configure(driver, device)
  device:configure()
end

local function handle_lock_door(driver, device, zb_rx)
  local function query_device()
    device:send(DoorLock.attributes.LockState:read(device))
  end
  device.thread:call_with_delay(5, query_device)
end

local lock_without_codes = {
  NAME = "Zigbee Lock Without Codes",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure
  },
  capability_handlers = {
    [capabilities.lock.ID] = {
      [capabilities.lock.commands.lock.NAME] = handle_lock,
      [capabilities.lock.commands.unlock.NAME] = handle_unlock
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zigbee_handlers = {
    cluster = {
      [DoorLock.ID] = {
        [DoorLock.commands.LockDoorResponse.ID] = handle_lock_door,
        [DoorLock.commands.UnlockDoorResponse.ID] = handle_lock_door,
      }
    },
    attr = {
      [DoorLock.ID] = {
        [DoorLock.attributes.NumberOfPINUsersSupported.ID] = function() end -- just to make sure we don't switch profiles
      }
    }
  },
  can_handle = can_handle_lock_without_codes
}

return lock_without_codes
