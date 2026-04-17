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
  [capabilities.remoteControlStatus.ID] = capabilities.remoteControlStatus.remoteControlEnabled("false"),
  [capabilities.switch.ID] = capabilities.switch.switch.off()
}

local function added_handler(self, device)
  for id, event in pairs(initial_events_map) do
    if device:supports_capability_by_id(id) then
      device:emit_event(event)
    end
  end
end

--- Only ever fires when the device attempts to turn the switch back on and this is rejected.
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.ApplicationStatus.ApplicationRejectedRequest
local function app_rejected_handler(driver, device, cmd)
  print("Application rejected received from device, unable to rearm")
  _deviceState["switch_state"] = false
  --- Reset the UI switch to match the current relay state.
  device:emit_event(capabilities.switch.switch.off({state_change = true}))
end

local function device_init(self, device)
  print("Device init: Z-Wave Appliance Safety Shutoff")
  -- TODO: What to do on device initalization
  -- Get binary switch information, Report should handle asynchronously
  device:send(SwitchBinary:Get({}))
  -- if (device:supports_capability(capabilities.powerMeter)) then
  --   device:send(Notification:Get({notification_type = Notification.notification_type.power_management}))
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
  -- TODO: fix device changing value
  local isDeviceChanging = false;
  if cmd.args.value == SwitchBinary.value.OFF_DISABLE then
    device:emit_event(capabilities.switch.switch.off({state_change = isDeviceChanging}))
    --- Also turn off power meter UI element, appliance is obviously not drawing power if
    --- the switch is off
    if (device:supports_capability(capabilities.applianceUtilization)) then
      device:emit_event(capabilities.applianceUtilization.status.notInUse())
    end
  else
    device:emit_event(capabilities.switch.switch.on({state_change = isDeviceChanging}))
  end
end

--- Handle a Switch OFF command from the application.
--- Switching on is not allowed in many cases so that behavior
--- is inherited by the subdriver as needed. 
--- 
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param command ST level capability command
local function st_switch_off_handler(driver, device, command)
  device:send(SwitchBinary:Set({
      target_value = SwitchBinary.value.OFF_DISABLE,
      duration = 0
    })
  )
  device:send(SwitchBinary:Get({}))
end

--- Handle a Switch ON command from the application.
--- Switching on is not allowed in many cases so that behavior
--- is inherited by the subdriver as needed. 
--- 
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param command ST level capability command
local function st_switch_on_handler(driver, device, command)
  device:send(SwitchBinary:Set({
      target_value = SwitchBinary.value.ON_ENABLE,
      duration = 0
    })
  )
  device:send(SwitchBinary:Get({}))
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
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.off.NAME] = st_switch_off_handler,
      [capabilities.switch.commands.on.NAME] = st_switch_on_handler
    },
    [capabilities.soundDetection.ID] = {
      [capabilities.soundDetection.commands.disableSoundDetection.NAME] = st_sound_detection_disable_handler,
      [capabilities.soundDetection.commands.enableSoundDetection.NAME] = st_sound_detection_enable_handler,
    }
  },
  zwave_handlers = {
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = switch_report_handler,
    },
    [cc.APPLICATION_STATUS] = {
      [ApplicationStatus.APPLICATION_REJECTED_REQUEST] = app_rejected_handler,
    }
  }
}

--- @type st.zwave.Driver
local safety_shutoff = ZwaveDriver("zwave_appliance_safety", driver_template)
safety_shutoff:run()
