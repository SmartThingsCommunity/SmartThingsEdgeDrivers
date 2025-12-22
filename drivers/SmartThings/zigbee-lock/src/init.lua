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

-- Zigbee Driver utilities
local defaults          = require "st.zigbee.defaults"
local device_management = require "st.zigbee.device_management"
local ZigbeeDriver      = require "st.zigbee"

-- Zigbee Spec Utils
local clusters                = require "st.zigbee.zcl.clusters"
local Alarm                   = clusters.Alarms
local LockCluster             = clusters.DoorLock
local PowerConfiguration      = clusters.PowerConfiguration

-- Capabilities
local capabilities              = require "st.capabilities"
local Battery                   = capabilities.battery
local Lock                      = capabilities.lock
local LockCodes                 = capabilities.lockCodes
local LockCredentials           = capabilities.lockCredentials
local LockUsers                 = capabilities.lockUsers

-- Enums
local UserStatusEnum            = LockCluster.types.DrlkUserStatus
local UserTypeEnum              = LockCluster.types.DrlkUserType
local ProgrammingEventCodeEnum  = LockCluster.types.ProgramEventCode

local socket = require "cosock.socket"
local lock_utils = require "lock_utils"

local DELAY_LOCK_EVENT = "_delay_lock_event"
local MAX_DELAY = 10

local function lazy_load_if_possible(sub_driver_name)
  -- gets the current lua libs api version
  local version = require "version"

  -- version 9 will include the lazy loading functions
  if version.api >= 9 then
    return ZigbeeDriver.lazy_load_sub_driver(require(sub_driver_name))
  else
    return require(sub_driver_name)
  end
end

local refresh = function(driver, device, cmd)
  device:refresh()
  device:send(LockCluster.attributes.LockState:read(device))
  device:send(Alarm.attributes.AlarmCount:read(device))
  -- we can't determine from fingerprints if devices support lock codes, so
  -- here in the driver we'll do a check once to see if the device responds here
  -- and if it does, we'll switch it to a profile with lock codes
  if not device:supports_capability_by_id(LockCodes.ID) and not device:get_field(lock_utils.CHECKED_CODE_SUPPORT) then
    device:send(LockCluster.attributes.NumberOfPINUsersSupported:read(device))
    -- we won't make this value persist because it's not that important
    device:set_field(lock_utils.CHECKED_CODE_SUPPORT, true)
  end
end

local alarm_handler = function(driver, device, zb_mess)
  local ALARM_REPORT = {
    [0] = Lock.lock.unknown(),
    [1] = Lock.lock.unknown(),
    -- Events 16-19 are low battery events, but are presented as descriptionText only
  }
  if (ALARM_REPORT[zb_mess.body.zcl_body.alarm_code.value] ~= nil) then
    device:emit_event(ALARM_REPORT[zb_mess.body.zcl_body.alarm_code.value])
  end
end

  -- this command should now trigger setting the migrated field and reinjecting the command.
  -- this is so we can start using the new capbilities from now on.
local function device_added(driver, device)
  if device:supports_capability_by_id(LockCodes.ID) then
    device:emit_event(LockCodes.migrated(true, { state_change = true, visibility = { displayed = true } }))
    if device.device_added ~= nil then
      -- make the driver call this command again, it will now be handled in new capabilities.
      driver.lifecycle_handlers.device_added(driver, device)
    end
  else
    lock_utils.populate_state_from_data(device)
    driver:inject_capability_command(device, {
      capability = capabilities.refresh.ID,
      command = capabilities.refresh.commands.refresh.NAME,
      args = {}
    })
  end
end

local function init(driver, device)
  lock_utils.populate_state_from_data(device)
  -- temp fix before this can be changed to non-persistent
  device:set_field(lock_utils.CODE_STATE, nil, { persist = true })
end

-- The following two functions are from the lock defaults. They are in the base driver temporarily
-- until the fix is widely released in the lua libs
local lock_state_handler = function(driver, device, value, zb_rx)
  local attr = capabilities.lock.lock
  local LOCK_STATE = {
    [value.NOT_FULLY_LOCKED]     = attr.unknown(),
    [value.LOCKED]               = attr.locked(),
    [value.UNLOCKED]             = attr.unlocked(),
    [value.UNDEFINED]            = attr.unknown(),
  }

  -- this is where we decide whether or not we need to delay our lock event because we've
  -- observed it coming before the event (or we're starting to compute the timer)
  local delay = device:get_field(DELAY_LOCK_EVENT) or 100
  if (delay < MAX_DELAY) then
    device.thread:call_with_delay(delay+.5, function ()
      device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, LOCK_STATE[value.value] or attr.unknown())
    end)
  else
    device:set_field(DELAY_LOCK_EVENT, socket.gettime())
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, LOCK_STATE[value.value] or attr.unknown())
  end
end

local function lock(driver, device, command)
  device:send_to_component(command.component, LockCluster.server.commands.LockDoor(device))
end

local function unlock(driver, device, command)
  device:send_to_component(command.component, LockCluster.server.commands.UnlockDoor(device))
end

local zigbee_lock_driver = {
  supported_capabilities = {
    Lock,
    LockCodes,
    Battery,
  },
  zigbee_handlers = {
    cluster = {
      [Alarm.ID] = {
        [Alarm.client.commands.Alarm.ID] = alarm_handler
      },
    },
    attr = {
      [LockCluster.ID] = {
        [LockCluster.attributes.LockState.ID] = lock_state_handler,
      }
    }
  },
  capability_handlers = {
    [Lock.ID] = {
      [Lock.commands.lock.NAME] = lock,
      [Lock.commands.unlock.NAME] = unlock,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh
    }
  },
  sub_drivers = {
    lazy_load_if_possible("using-old-capabilities"),
    lazy_load_if_possible("using-new-capabilities"),
  },
  lifecycle_handlers = {
    added = device_added,
    init = init,
  },
  health_check = false,
}

defaults.register_for_default_handlers(zigbee_lock_driver, zigbee_lock_driver.supported_capabilities)
local lock = ZigbeeDriver("zigbee-lock", zigbee_lock_driver)
lock:run()
