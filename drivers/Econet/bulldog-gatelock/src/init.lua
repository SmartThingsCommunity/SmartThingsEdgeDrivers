-- Econet GateLock Matter Edge Driver.
--
-- Built on st.matter.driver (NOT the generic st.driver) — this is the
-- Matter-specific driver class that actually attaches the secure
-- matter_channel session to each device. Using the generic Driver class
-- causes "matter_channel nil" because no Matter subsystem hookup happens.

local MatterDriver = require "st.matter.driver"
local clusters = require "st.matter.clusters"
local capabilities = require "st.capabilities"

local DoorLock           = clusters.DoorLock
local PowerSource        = clusters.PowerSource
local GeneralDiagnostics = clusters.GeneralDiagnostics

local UNLATCHED_STATE              = 0x3
local HARDWARE_FAULT_TAMPER_DETECTED = 10

----------------------------------------------------------------------
-- ATTRIBUTE HANDLERS
----------------------------------------------------------------------

local function lock_state_handler(driver, device, ib, response)
  local LockState = DoorLock.attributes.LockState
  local attr = capabilities.lock.lock
  local map = {
    [LockState.NOT_FULLY_LOCKED] = attr.not_fully_locked(),
    [LockState.LOCKED]           = attr.locked(),
    [LockState.UNLOCKED]         = attr.unlocked(),
    [UNLATCHED_STATE]            = attr.unlocked(),
  }
  if ib.data.value ~= nil and map[ib.data.value] then
    device:emit_event(map[ib.data.value])
  else
    device:emit_event(attr.not_fully_locked())
  end
end

local function door_state_handler(driver, device, ib, response)
  local val = ib.data.value
  if val == nil then return end
  if val == 1 then
    device:emit_event(capabilities.contactSensor.contact.closed())
  else
    device:emit_event(capabilities.contactSensor.contact.open())
  end
end

local function battery_percent_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

-- GeneralDiagnostics.ActiveHardwareFaults is a list of HardwareFaultEnum values.
-- Firmware adds kTamperDetected (10) when the keypad 4-strike brute-force
-- limit trips and removes it when the lockout expires. Map list membership
-- directly to the tamperAlert capability so the SmartThings UI tracks the
-- attribute's full lifecycle (detected -> clear) instead of just the alarm
-- event edge.
local function hardware_faults_handler(driver, device, ib, response)
  local list = ib.data and ib.data.elements
  local tampered = false
  if list ~= nil then
    for _, entry in ipairs(list) do
      if entry.value == HARDWARE_FAULT_TAMPER_DETECTED then
        tampered = true
        break
      end
    end
  end
  if tampered then
    device:emit_event(capabilities.tamperAlert.tamper.detected())
  else
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  end
end

----------------------------------------------------------------------
-- EVENT HANDLERS
----------------------------------------------------------------------

-- Retained for compatibility with firmware that only fires the
-- DoorLockAlarm event (older builds without GeneralDiagnostics tamper
-- reporting). On builds that report both, the attribute handler above
-- supersedes this by also clearing the state.
local function door_lock_alarm_handler(driver, device, ib, response)
  device:emit_event(capabilities.tamperAlert.tamper.detected())
end

----------------------------------------------------------------------
-- COMMAND HANDLERS
----------------------------------------------------------------------

local function handle_lock(driver, device, command)
  local ep = device:component_to_endpoint(command.component)
  device:send(DoorLock.server.commands.LockDoor(device, ep))
end

local function handle_unlock(driver, device, command)
  local ep = device:component_to_endpoint(command.component)
  device:send(DoorLock.server.commands.UnlockDoor(device, ep))
end

local function handle_refresh(driver, device, command)
  device:refresh()
end

----------------------------------------------------------------------
-- LIFECYCLE
----------------------------------------------------------------------

local function device_init(driver, device)
  device:subscribe()
end

local function device_added(driver, device)
  device:emit_event(capabilities.tamperAlert.tamper.clear())
end

----------------------------------------------------------------------
-- DRIVER TABLE  (passed as 2nd arg to MatterDriver)
----------------------------------------------------------------------

local matter_lock_driver = {
  lifecycle_handlers = {
    init  = device_init,
    added = device_added,
  },

  matter_handlers = {
    attr = {
      [DoorLock.ID] = {
        [DoorLock.attributes.LockState.ID] = lock_state_handler,
        [DoorLock.attributes.DoorState.ID] = door_state_handler,
      },
      [PowerSource.ID] = {
        [PowerSource.attributes.BatPercentRemaining.ID] = battery_percent_handler,
      },
      [GeneralDiagnostics.ID] = {
        [GeneralDiagnostics.attributes.ActiveHardwareFaults.ID] = hardware_faults_handler,
      },
    },
    event = {
      [DoorLock.ID] = {
        [DoorLock.events.DoorLockAlarm.ID] = door_lock_alarm_handler,
      },
    },
  },

  subscribed_attributes = {
    [capabilities.lock.ID] = {
      DoorLock.attributes.LockState,
    },
    [capabilities.contactSensor.ID] = {
      DoorLock.attributes.DoorState,
    },
    [capabilities.battery.ID] = {
      PowerSource.attributes.BatPercentRemaining,
    },
    [capabilities.tamperAlert.ID] = {
      GeneralDiagnostics.attributes.ActiveHardwareFaults,
    },
  },

  subscribed_events = {
    [capabilities.tamperAlert.ID] = {
      DoorLock.events.DoorLockAlarm,
    },
  },

  capability_handlers = {
    [capabilities.lock.ID] = {
      [capabilities.lock.commands.lock.NAME]   = handle_lock,
      [capabilities.lock.commands.unlock.NAME] = handle_unlock,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = handle_refresh,
    },
  },
}

local matter_driver = MatterDriver("econet-gatelock-matter", matter_lock_driver)
matter_driver:run()
