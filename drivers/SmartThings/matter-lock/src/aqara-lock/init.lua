-- Copyright 2024 SmartThings
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
local clusters = require "st.matter.clusters"
local device_lib = require "st.device"

local DoorLock = clusters.DoorLock
local AQARA_MANUFACTURER_ID = 0x115f

local function is_aqara_products(opts, driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and
      device.manufacturer_info.vendor_id == AQARA_MANUFACTURER_ID then
    return true
  end
  return false
end

local function find_default_endpoint(device, cluster)
  local res = device.MATTER_DEFAULT_ENDPOINT
  local eps = device:get_endpoints(cluster)
  table.sort(eps)
  for _, v in ipairs(eps) do
    if v ~= 0 then --0 is the matter RootNode endpoint
      return v
    end
  end
  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return res
end

local function component_to_endpoint(device, component_name)
  return find_default_endpoint(device, clusters.DoorLock.ID)
end

local function device_init(driver, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:subscribe()
 end

local function device_added(driver, device)
  device:emit_event(capabilities.lockAlarm.alarm.clear({state_change = true}))
end

local function lock_state_handler(driver, device, ib, response)
  local LockState = DoorLock.attributes.LockState
  local attr = capabilities.lock.lock
  local LOCK_STATE = {
    [LockState.NOT_FULLY_LOCKED] = attr.unknown(),
    [LockState.LOCKED] = attr.locked(),
    [LockState.UNLOCKED] = attr.unlocked(),
  }

  if ib.data.value ~= nil then
    device:emit_event(LOCK_STATE[ib.data.value])
  else
    device:emit_event(LOCK_STATE[LockState.NOT_FULLY_LOCKED])
  end
end

local function alarm_event_handler(driver, device, ib, response)
  local DlAlarmCode = DoorLock.types.DlAlarmCode
  local alarm_code = ib.data.elements.alarm_code
  if alarm_code.value == DlAlarmCode.LOCK_JAMMED then
    device:emit_event(capabilities.lockAlarm.alarm.unableToLockTheDoor({state_change = true}))
  elseif alarm_code.value == DlAlarmCode.LOCK_FACTORY_RESET then
    device:emit_event(capabilities.lockAlarm.alarm.lockFactoryReset({state_change = true}))
  elseif alarm_code.value == DlAlarmCode.WRONG_CODE_ENTRY_LIMIT then
    device:emit_event(capabilities.lockAlarm.alarm.attemptsExceeded({state_change = true}))
  elseif alarm_code.value == DlAlarmCode.FRONT_ESCEUTCHEON_REMOVED then
    device:emit_event(capabilities.lockAlarm.alarm.damaged({state_change = true}))
  elseif alarm_code.value == DlAlarmCode.DOOR_FORCED_OPEN then
    device:emit_event(capabilities.lockAlarm.alarm.forcedOpeningAttempt({state_change = true}))
  end
end

local function handle_refresh(driver, device, command)
  local req = DoorLock.attributes.LockState:read(device)
  device:send(req)
end

local function handle_lock(driver, device, command)
  local ep = device:component_to_endpoint(command.component)
  device:send(DoorLock.server.commands.LockDoor(device, ep))
end

local function handle_unlock(driver, device, command)
  local ep = device:component_to_endpoint(command.component)
  device:send(DoorLock.server.commands.UnlockDoor(device, ep))
end

local aqara_lock_handler = {
  NAME = "Aqara Lock Handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
  },
  matter_handlers = {
    attr = {
      [DoorLock.ID] = {
        [DoorLock.attributes.LockState.ID] = lock_state_handler
      },
    },
    event = {
      [DoorLock.ID] = {
        [DoorLock.events.DoorLockAlarm.ID] = alarm_event_handler
      },
    },
  },
  subscribed_attributes = {
    [capabilities.lock.ID] = {DoorLock.attributes.LockState}
  },
  subscribed_events = {
    [capabilities.lockAlarm.ID] = {
      DoorLock.events.DoorLockAlarm
    },
  },
  capability_handlers = {
    [capabilities.lock.ID] = {
      [capabilities.lock.commands.lock.NAME] = handle_lock,
      [capabilities.lock.commands.unlock.NAME] = handle_unlock,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = handle_refresh
    },
  },
  supported_capabilities = {
    capabilities.lock,
    capabilities.lockAlarm
  },
  can_handle = is_aqara_products
}

return aqara_lock_handler