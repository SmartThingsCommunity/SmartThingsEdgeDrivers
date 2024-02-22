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

-- Enums
local UserStatusEnum            = LockCluster.types.DrlkUserStatus
local UserTypeEnum              = LockCluster.types.DrlkUserType
local ProgrammingEventCodeEnum  = LockCluster.types.ProgramEventCode

local socket = require "cosock.socket"
local lock_utils = require "lock_utils"

local DELAY_LOCK_EVENT = "_delay_lock_event"
local MAX_DELAY = 10

local reload_all_codes = function(driver, device, command)
  -- starts at first user code index then iterates through all lock codes as they come in
  device:send(LockCluster.attributes.SendPINOverTheAir:write(device, true))
  if (device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodeLength.NAME) == nil) then
    device:send(LockCluster.attributes.MaxPINCodeLength:read(device))
  end
  if (device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.minCodeLength.NAME) == nil) then
    device:send(LockCluster.attributes.MinPINCodeLength:read(device))
  end
  if (device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME) == nil) then
    device:send(LockCluster.attributes.NumberOfPINUsersSupported:read(device))
  end
  if (device:get_field(lock_utils.CHECKING_CODE) == nil) then device:set_field(lock_utils.CHECKING_CODE, 0) end
  device:emit_event(LockCodes.scanCodes("Scanning", { visibility = { displayed = false } }))
  device:send(LockCluster.server.commands.GetPINCode(device, device:get_field(lock_utils.CHECKING_CODE)))
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

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 600, 21600, 1))

  device:send(device_management.build_bind_request(device, LockCluster.ID, self.environment_info.hub_zigbee_eui))
  device:send(LockCluster.attributes.LockState:configure_reporting(device, 0, 3600, 0))

  device:send(device_management.build_bind_request(device, Alarm.ID, self.environment_info.hub_zigbee_eui))
  device:send(Alarm.attributes.AlarmCount:configure_reporting(device, 0, 21600, 0))

  -- Don't send a reload all codes if this is a part of migration
  if device.data.lockCodes == nil or device:get_field(lock_utils.MIGRATION_RELOAD_SKIPPED) == true then
    device.thread:call_with_delay(2, function(d)
      self:inject_capability_command(device, {
        capability = capabilities.lockCodes.ID,
        command = capabilities.lockCodes.commands.reloadAllCodes.NAME,
        args = {}
      })
    end)
  else
    device:set_field(lock_utils.MIGRATION_RELOAD_SKIPPED, true, { persist = true })
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

local get_pin_response_handler = function(driver, device, zb_mess)
  local event = LockCodes.codeChanged("", { state_change = true })
  local code_slot = tostring(zb_mess.body.zcl_body.user_id.value)
  event.data = {codeName = lock_utils.get_code_name(device, code_slot)}
  if (zb_mess.body.zcl_body.user_status.value == UserStatusEnum.OCCUPIED_ENABLED) then
    -- Code slot is occupied
    event.value = code_slot .. lock_utils.get_change_type(device, code_slot)
    local lock_codes = lock_utils.get_lock_codes(device)
    lock_codes[code_slot] = event.data.codeName
    device:emit_event(event)
    lock_utils.lock_codes_event(device, lock_codes)
    lock_utils.reset_code_state(device, code_slot)
  else
    -- Code slot is unoccupied
    if (lock_utils.get_lock_codes(device)[code_slot] ~= nil) then
      -- Code has been deleted
      lock_utils.lock_codes_event(device, lock_utils.code_deleted(device, code_slot))
    else
      -- Code is unset
      event.value = code_slot .. " unset"
      device:emit_event(event)
    end
  end

  code_slot = tonumber(code_slot)
  if (code_slot == device:get_field(lock_utils.CHECKING_CODE)) then
    -- the code we're checking has arrived
    if (code_slot >= device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME)) then
      device:emit_event(LockCodes.scanCodes("Complete", { visibility = { displayed = false } }))
      device:set_field(lock_utils.CHECKING_CODE, nil)
    else
      local checkingCode = device:get_field(lock_utils.CHECKING_CODE) + 1
      device:set_field(lock_utils.CHECKING_CODE, checkingCode)
      device:send(LockCluster.server.commands.GetPINCode(device, checkingCode))
    end
  end
end

local programming_event_handler = function(driver, device, zb_mess)
  local event = LockCodes.codeChanged("", { state_change = true })
  local code_slot = tostring(zb_mess.body.zcl_body.user_id.value)
  event.data = {}
  if (zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.MASTER_CODE_CHANGED) then
    -- Master code changed
    event.value = "0 set"
    event.data = {codeName = "Master Code"}
    device:emit_event(event)
  elseif (zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.PIN_CODE_DELETED) then
    if (zb_mess.body.zcl_body.user_id.value == 0xFF) then
      -- All codes deleted
      for cs, _ in pairs(lock_utils.get_lock_codes(device)) do
        lock_utils.code_deleted(device, cs)
      end
      lock_utils.lock_codes_event(device, {})
    else
      -- One code deleted
      if (lock_utils.get_lock_codes(device)[code_slot] ~= nil) then
        lock_utils.lock_codes_event(device, lock_utils.code_deleted(device, code_slot))
      end
    end
  elseif (zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.PIN_CODE_ADDED or
          zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.PIN_CODE_CHANGED) then
    -- Code added or changed
    local change_type = lock_utils.get_change_type(device, code_slot)
    local code_name = lock_utils.get_code_name(device, code_slot)
    event.value = code_slot .. change_type
    event.data = {codeName = code_name}
    device:emit_event(event)
    if (change_type == " set") then
      local lock_codes = lock_utils.get_lock_codes(device)
      lock_codes[code_slot] = code_name
      lock_utils.lock_codes_event(device, lock_codes)
    end
  end
end

local handle_max_codes = function(driver, device, value)
  if value.value ~= 0 then
    -- Here's where we'll end up if we queried a lock whose profile does not have lock codes,
    -- but it gave us a non-zero number of pin users, so we want to switch the profile
    if not device:supports_capability_by_id(LockCodes.ID) then
      device:try_update_metadata({profile = "base-lock"}) -- switch to a lock with codes
      lock_utils.populate_state_from_data(device) -- if this was a migrated device, try to migrate the lock codes
      if not device:get_field(lock_utils.MIGRATION_COMPLETE) then -- this means we didn't find any pre-migration lock codes
        -- so we'll load them manually
        driver:inject_capability_command(device, {
          capability = capabilities.lockCodes.ID,
          command = capabilities.lockCodes.commands.reloadAllCodes.NAME,
          args = {}
        })
      end
    end
    device:emit_event(LockCodes.maxCodes(value.value, { visibility = { displayed = false } }))
  end
end

local handle_max_code_length = function(driver, device, value)
  device:emit_event(LockCodes.maxCodeLength(value.value, { visibility = { displayed = false } }))
end

local handle_min_code_length = function(driver, device, value)
  device:emit_event(LockCodes.minCodeLength(value.value, { visibility = { displayed = false } }))
end

local update_codes = function(driver, device, command)
  local delay = 0
  -- args.codes is json
  for name, code in pairs(command.args.codes) do
    -- these seem to come in the format "code[slot#]: code"
    local code_slot = tonumber(string.gsub(name, "code", ""), 10)
    if (code_slot ~= nil) then
      if (code ~= nil and (code ~= "0" and code ~= "")) then
        device.thread:call_with_delay(delay, function ()
          device:send(LockCluster.server.commands.SetPINCode(device,
                code_slot,
                UserStatusEnum.OCCUPIED_ENABLED,
                UserTypeEnum.UNRESTRICTED,
                code))
        end)
        delay = delay + 2
      else
        device.thread:call_with_delay(delay, function ()
          device:send(LockCluster.server.commands.ClearPINCode(device, code_slot))
        end)
        delay = delay + 2
      end
      device.thread:call_with_delay(delay, function(d)
        device:send(LockCluster.server.commands.GetPINCode(device, code_slot))
      end)
      delay = delay + 2
    end
  end
end

local delete_code = function(driver, device, command)
  device:send(LockCluster.attributes.SendPINOverTheAir:write(device, true))
  device:send(LockCluster.server.commands.ClearPINCode(device, command.args.codeSlot))
  device.thread:call_with_delay(2, function(d)
    device:send(LockCluster.server.commands.GetPINCode(device, command.args.codeSlot))
  end)
end

local request_code = function(driver, device, command)
  device:send(LockCluster.server.commands.GetPINCode(device, command.args.codeSlot))
end

local set_code = function(driver, device, command)
  if (command.args.codePIN == "") then
    driver:inject_capability_command(device, {
      capability = capabilities.lockCodes.ID,
      command = capabilities.lockCodes.commands.nameSlot.NAME,
      args = {command.args.codeSlot, command.args.codeName}
    })
  else
    device:send(LockCluster.server.commands.SetPINCode(device,
            command.args.codeSlot,
            UserStatusEnum.OCCUPIED_ENABLED,
            UserTypeEnum.UNRESTRICTED,
            command.args.codePIN)
    )
    if (command.args.codeName ~= nil) then
      -- wait for confirmation from the lock to commit this to memory
      -- Groovy driver has a lot more info passed here as a description string, may need to be investigated
      local codeState = device:get_field(lock_utils.CODE_STATE) or {}
      codeState["setName"..command.args.codeSlot] = command.args.codeName
      device:set_field(lock_utils.CODE_STATE, codeState, { persist = true })
    end

    device.thread:call_with_delay(4, function(d)
      device:send(LockCluster.server.commands.GetPINCode(device, command.args.codeSlot))
    end)
  end
end

local name_slot = function(driver, device, command)
  local code_slot = tostring(command.args.codeSlot)
  local lock_codes = lock_utils.get_lock_codes(device)
  if (lock_codes[code_slot] ~= nil) then
    lock_codes[code_slot] = command.args.codeName
    device:emit_event(LockCodes.codeChanged(code_slot .. " renamed", { state_change = true }))
    lock_utils.lock_codes_event(device, lock_codes)
  end
end

local function device_added(driver, device)
  lock_utils.populate_state_from_data(device)

  driver:inject_capability_command(device, {
    capability = capabilities.refresh.ID,
    command = capabilities.refresh.commands.refresh.NAME,
    args = {}
  })
end

local function init(driver, device)
  lock_utils.populate_state_from_data(device)
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
      device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, LOCK_STATE[value.value])
    end)
  else
    device:set_field(DELAY_LOCK_EVENT, socket.gettime())
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, LOCK_STATE[value.value])
  end
end

local lock_operation_event_handler = function(driver, device, zb_rx)
  local event_code = zb_rx.body.zcl_body.operation_event_code.value
  local source = zb_rx.body.zcl_body.operation_event_source.value
  local OperationEventCode = require "st.zigbee.generated.zcl_clusters.DoorLock.types.OperationEventCode"
  local METHOD = {
    [0] = "keypad",
    [1] = "command",
    [2] = "manual",
    [3] = "rfid",
    [4] = "fingerprint",
    [5] = "bluetooth"
  }
  local STATUS = {
    [OperationEventCode.LOCK]            = capabilities.lock.lock.locked(),
    [OperationEventCode.UNLOCK]          = capabilities.lock.lock.unlocked(),
    [OperationEventCode.ONE_TOUCH_LOCK]  = capabilities.lock.lock.locked(),
    [OperationEventCode.KEY_LOCK]        = capabilities.lock.lock.locked(),
    [OperationEventCode.KEY_UNLOCK]      = capabilities.lock.lock.unlocked(),
    [OperationEventCode.AUTO_LOCK]       = capabilities.lock.lock.locked(),
    [OperationEventCode.MANUAL_LOCK]     = capabilities.lock.lock.locked(),
    [OperationEventCode.MANUAL_UNLOCK]   = capabilities.lock.lock.unlocked(),
    [OperationEventCode.SCHEDULE_LOCK]   = capabilities.lock.lock.locked(),
    [OperationEventCode.SCHEDULE_UNLOCK] = capabilities.lock.lock.unlocked()
  }
  local event = STATUS[event_code]
  if (event ~= nil) then
    event["data"] = {}
    if (event_code == OperationEventCode.AUTO_LOCK or
        event_code == OperationEventCode.SCHEDULE_LOCK or
        event_code == OperationEventCode.SCHEDULE_UNLOCK
      ) then
      event.data.method = "auto"
    else
      event.data.method = METHOD[source]
    end
    if (source == 0) then --keypad
      local code_id = zb_rx.body.zcl_body.user_id.value
      local code_name = "Code "..code_id
      local lock_codes = device:get_field("lockCodes")
      if (lock_codes ~= nil and
          lock_codes[code_id] ~= nil) then
        code_name = lock_codes[code_id]
      end
      event.data = {method = METHOD[0], codeId = code_id .. "", codeName = code_name}
    end

    -- if this is an event corresponding to a recently-received attribute report, we
    -- want to set our delay timer for future lock attribute report events
    if device:get_latest_state(
        device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value),
        capabilities.lock.ID,
        capabilities.lock.lock.ID) == event.value.value then
      local preceding_event_time = device:get_field(DELAY_LOCK_EVENT) or 0
      local time_diff = socket.gettime() - preceding_event_time
      if time_diff < MAX_DELAY then
        device:set_field(DELAY_LOCK_EVENT, time_diff)
      end
    end

    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, event)
  end
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
      [LockCluster.ID] = {
        [LockCluster.client.commands.GetPINCodeResponse.ID] = get_pin_response_handler,
        [LockCluster.client.commands.ProgrammingEventNotification.ID] = programming_event_handler,
        [LockCluster.client.commands.OperatingEventNotification.ID] = lock_operation_event_handler
      }
    },
    attr = {
      [LockCluster.ID] = {
        [LockCluster.attributes.LockState.ID] = lock_state_handler,
        [LockCluster.attributes.MaxPINCodeLength.ID] = handle_max_code_length,
        [LockCluster.attributes.MinPINCodeLength.ID] = handle_min_code_length,
        [LockCluster.attributes.NumberOfPINUsersSupported.ID] = handle_max_codes
      }
    }
  },
  capability_handlers = {
    [LockCodes.ID] = {
      [LockCodes.commands.updateCodes.NAME] = update_codes,
      [LockCodes.commands.deleteCode.NAME] = delete_code,
      [LockCodes.commands.reloadAllCodes.NAME] = reload_all_codes,
      [LockCodes.commands.requestCode.NAME] = request_code,
      [LockCodes.commands.setCode.NAME] = set_code,
      [LockCodes.commands.nameSlot.NAME] = name_slot,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh
    }
  },
  sub_drivers = {
    require("samsungsds"),
    require("yale"),
    require("yale-fingerprint-lock"),
    require("lock-without-codes")
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
    added = device_added,
    init = init,
  }
}

defaults.register_for_default_handlers(zigbee_lock_driver, zigbee_lock_driver.supported_capabilities)
local lock = ZigbeeDriver("zigbee-lock", zigbee_lock_driver)
lock:run()
