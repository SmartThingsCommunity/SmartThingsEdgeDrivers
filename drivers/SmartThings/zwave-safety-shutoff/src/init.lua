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
--- @type st.zwave.CommandClass.ApplicationStatus
local ApplicationStatus = (require "st.zwave.CommandClass.ApplicationStatus")({ version = 1 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })

local function lazy_load_if_possible(sub_driver_name)
  -- gets the current lua libs api version
  local version = require "version"

  -- version 9 will include the lazy loading functions
  if version.api >= 9 then
    return ZwaveDriver.lazy_load_sub_driver(require(sub_driver_name))
  else
    return require(sub_driver_name)
  end
end

local initial_events_map = {
  [capabilities.soundDetection.ID] = capabilities.soundDetection.soundDetected.noSound(),
  [capabilities.applianceUtilization.ID] = capabilities.applianceUtilization.status.notInUse(),
}

local function added_handler(self, device)
  for id, event in pairs(initial_events_map) do
    if device:supports_capability_by_id(id) then
      device:emit_event(event)
      -- Also emit event specifying the supported soundDetected types and setup functions
      if id == capabilities.soundDetection.ID then
          device:emit_event(capabilities.soundDetection.supportedSoundTypes({"noSound", "fireAlarm"}, {visibility = { displayed = false }}))
          device:emit_event(capabilities.soundDetection.soundDetectionState("enabled", {visibilty = {displayed = false}}))
      end
    end
  end
end

local function device_init(self, device)
  print("Device init: Z-Wave Appliance Safety Shutoff")
  -- Get binary switch information, Report should handle asynchronously
  device:send(SwitchBinary:Get({}))
  -- Get current state of the notifications
  -- Smoke Alarm (supported by all devices)
  device:send(Notification:Get({
    v1_alarm_type = 0,
    notification_type = Notification.notification_type.SMOKE,
    event = Notification.event.smoke.DETECTED
  }))
  -- Gas unit doesn't support appliance utilization.
  -- If supported, get state of appliance power.
  if (device:supports_capability(capabilities.applianceUtilization)) then
    device:send(Notification:Get({
      v1_alarm_type = 0,
      notification_type = Notification.notification_type.POWER_MANAGEMENT,
      event = Notification.event.power_management.POWER_HAS_BEEN_APPLIED
    }))
  end
end

local function do_refresh(self, device)
  device_init(self, device);
end

local function info_changed(self, device)
  device_init(self, device)
end

--- Handle a Z-Wave Command Class Binary Switch report, translate this to
--- an equivalent SmartThings Capability event, and emit this to the
--- SmartThings infrastructure.
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.SwitchBinary.Report
local function switch_report_handler(driver, device, cmd)
  -- This is the only place the switch_state mirror should change value.
  local isDeviceChanging = true -- Eventually trigger this if needed based on current status
  local useValve = device:supports_capability(capabilities.safetyValve)
  if cmd.args.value == SwitchBinary.value.OFF_DISABLE then
    if useValve then 
      device:emit_event(capabilities.safetyValve.valve.closed())
    else 
      device:emit_event(capabilities.switch.switch.off({state_change = isDeviceChanging}))
    end
    --- Also turn off power meter UI element, appliance is obviously not drawing power if
    --- the switch is off
    if (device:supports_capability(capabilities.applianceUtilization)) then
      device:emit_event(capabilities.applianceUtilization.status.notInUse())
    end
  else
    if useValve then
      device:emit_event(capabilities.safetyValve.valve.open({state_change = isDeviceChanging}))
    else 
      device:emit_event(capabilities.switch.switch.on({state_change = isDeviceChanging}))
    end 
  end
end


--- Handler for notification report command class from sensor
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Notification.Report
local function notification_report_handler(self, device, cmd)
  local event = nil
  local status = nil
  local set_status = device:get_field("notification_set_status")
  if cmd.args.notification_type == Notification.notification_type.SMOKE then
    -- First, ensure that control is still valid
    if (cmd.args.notification_status == Notification.notification_status.OFF and set_status == "sound_disable") then -- State IDLE is 0, this may be a report for notifications enabled.
      status = capabilities.soundDetection.soundDetectionState.disabled()
      print("Notifications disabled successfully")
    elseif (set_status == "sound_enable") then
      status = capabilities.soundDetection.soundDetectionState.enabled()
      print("Notifications enabled successfully")
    end

    if (set_status == nil or set_status ~= "none") then
      device:set_field("notification_set_status", "none")
    end
    -- Now check and see what the sound state is
    if cmd.args.event == Notification.event.smoke.DETECTED then
      event = capabilities.soundDetection.soundDetected.fireAlarm()
    elseif cmd.args.event == Notification.event.smoke.STATE_IDLE then
      event = capabilities.soundDetection.soundDetected.noSound()
    end
  elseif (device:supports_capability(capabilities.applianceUtilization) and cmd.args.notification_type == Notification.notification_type.POWER_MANAGEMENT) then
    if (cmd.args.event == Notification.event.power_management.POWER_HAS_BEEN_APPLIED) then
      event = capabilities.applianceUtilization.status.inUse()
    elseif (cmd.args.event == Notification.event.power_management.STATE_IDLE) then
      event = capabilities.applianceUtilization.status.notInUse()
    end
  end
  -- While the device supports other notifications, they are out of scope for WWST certification.
  if status ~= nil then 
    print("Notification status %s set", status)
    device:emit_event(status) 
  end
  if event ~= nil then 
    print("Notification event: %s", event)
    device:emit_event(event) 
  end
end


--- Handle a 'Disable sound detection' command from SmartThings.
--- 
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param command ST level capability command
local function st_sound_detection_disable_handler(driver, device, command)
  device:send(Notification:Set({
      notification_type = Notification.notification_type.SMOKE,
      notification_status = Notification.notification_status.OFF
    })
  )
  device:send(Notification:Get({
      v1_alarm_type = 0,
      notification_type = Notification.notification_type.SMOKE,
      event = Notification.event.smoke.DETECTED
    })
  )
  device:set_field("notification_set_status", "sound_disable")
end

--- Handle an 'Enable sound detection' command from SmartThings.
--- 
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param command ST level capability command
local function st_sound_detection_enable_handler(driver, device, command)
  device:send(Notification:Set({
      notification_type = Notification.notification_type.SMOKE,
      notification_status = Notification.notification_status.ON
    })
  )
  device:send(Notification:Get({
      v1_alarm_type = 0,
      notification_type = Notification.notification_type.SMOKE,
      event = Notification.event.smoke.DETECTED
    })
  )
  device:set_field("notification_set_status", "sound_enable")
end

local driver_template = {
  sub_drivers = {
    lazy_load_if_possible("fireavert-appliance-shutoff-gas"),
    lazy_load_if_possible("fireavert-appliance-shutoff-electric"),
  },
  lifecycle_handlers = {
    added = added_handler,
    init = device_init,
    infoChanged = info_changed
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [capabilities.soundDetection.ID] = {
      [capabilities.soundDetection.commands.disableSoundDetection.NAME] = st_sound_detection_disable_handler,
      [capabilities.soundDetection.commands.enableSoundDetection.NAME] = st_sound_detection_enable_handler,
    }
  },
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler,
    },
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = switch_report_handler,
    }
  }
}

--- @type st.zwave.Driver
local safety_shutoff = ZwaveDriver("zwave_appliance_safety", driver_template)
safety_shutoff:run()
