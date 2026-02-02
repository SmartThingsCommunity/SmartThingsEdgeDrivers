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
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 11 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })

local log = require "log"

local MoldHealthConcern = capabilities.moldHealthConcern
local ContactSensor = capabilities.contactSensor
local PowerSource = capabilities.powerSource
local ThreeAxis = capabilities.threeAxis
local TamperAlert = capabilities.tamperAlert

local AEOTEC_DOOR_WINDOW_SENSOR_8_FINGERPRINTS = {
  { manufacturerId = 0x0371, productId = 0x0037 } -- Aeotec Door Window Sensor 8 EU/US/AU
}

local function can_handle_aeotec_door_window_sensor_8(opts, driver, device, ...)
  for _, fingerprint in ipairs(AEOTEC_DOOR_WINDOW_SENSOR_8_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      local subdriver = require("aeotec-door-window-sensor-8")
      return true, subdriver
    end
  end
  return false
end

local function added_handler(driver, device)
  device:send(Configuration:Get({ parameter_number = 10 }))

  device:emit_event(MoldHealthConcern.supportedMoldValues({"good", "moderate"}))
  
  -- Default value
  device:emit_event(MoldHealthConcern.moldHealthConcern.good())

  -- Default value
  device:emit_event(PowerSource.powerSource.battery())
  
  device:send(Battery:Get({}))
end

local function device_init(driver, device)
  device:set_field("three_axis_x", 0)
  device:set_field("three_axis_y", 0)
  device:set_field("three_axis_z", 0)
end

local function do_refresh(driver, device)
  device:send(Battery:Get({}))
end

local function notification_report_handler(self, device, cmd)
  local event

  -- DOOR_WINDOW
  if cmd.args.notification_type == Notification.notification_type.ACCESS_CONTROL then
    if cmd.args.event == Notification.event.access_control.WINDOW_DOOR_IS_CLOSED then
      event = ContactSensor.contact.closed()
    elseif cmd.args.event == Notification.event.access_control.WINDOW_DOOR_IS_OPEN then
      event = ContactSensor.contact.open()
    end
  end

  -- POWER
  if cmd.args.notification_type == Notification.notification_type.POWER_MANAGEMENT then
    if cmd.args.event == Notification.event.power_management.AC_MAINS_DISCONNECTED then
      event = PowerSource.powerSource.battery()
    elseif cmd.args.event == Notification.event.power_management.AC_MAINS_RE_CONNECTED then
      event = PowerSource.powerSource.mains()
    elseif cmd.args.event == Notification.event.power_management.POWER_HAS_BEEN_APPLIED then
      device:send(Battery:Get({}))
    end
  end

  -- MOLD
  if cmd.args.notification_type == Notification.notification_type.WEATHER_ALARM then
    if cmd.args.event == Notification.event.weather_alarm.STATE_IDLE then
      event = MoldHealthConcern.moldHealthConcern.good()
    elseif cmd.args.event == Notification.event.weather_alarm.MOISTURE_ALARM then
      event = MoldHealthConcern.moldHealthConcern.moderate()
    end
  end

  -- TAMPER
  if cmd.args.notification_type == Notification.notification_type.HOME_SECURITY then
    if cmd.args.event == Notification.event.home_security.STATE_IDLE then
      log.info("STATE_IDLE")
      event = TamperAlert.tamper.clear()
    elseif cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED then
      log.info("TAMPERING_PRODUCT_COVER_REMOVED")
      event = TamperAlert.tamper.detected()
    end
  end

  if (event ~= nil) then
    device:emit_event(event)
  end
end

local function sensor_multilevel_report_handler(self, device, cmd) 
  local event
  local sensor_type = cmd.args.sensor_type
  local value = cmd.args.sensor_value
  
  local x = device:get_field("three_axis_x") or 0
  local y = device:get_field("three_axis_y") or 0
  local z = device:get_field("three_axis_z") or 0

  local MIN_VAL = -10000
  local MAX_VAL = 10000
  -- log.info(string.format("SensorMultilevel: type=%d, raw=%.1f", sensor_type, value))
  value = math.max(MIN_VAL, math.min(MAX_VAL, value))
  -- log.info(string.format("Clamped: %.1f", value))

  if (sensor_type == SensorMultilevel.sensor_type.ACCELERATION_X_AXIS) then
    x = value
    device:set_field("three_axis_x", x)
    event = ThreeAxis.threeAxis(x, y, z)
  elseif (sensor_type == SensorMultilevel.sensor_type.ACCELERATION_Y_AXIS) then
    y = value
    device:set_field("three_axis_y", y)
    event = ThreeAxis.threeAxis(x, y, z)
  elseif (sensor_type == SensorMultilevel.sensor_type.ACCELERATION_Z_AXIS) then
    z = value
    device:set_field("three_axis_z", z)
    event = ThreeAxis.threeAxis(x, y, z)
  end

  if (event ~= nil) then
    device:emit_event(event)
  end
end

local aeotec_door_window_sensor_8 = {
  supported_capabilities = {
    capabilities.powerSource,
    capabilities.threeAxis,
  },
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
    -- [cc.SENSOR_MULTILEVEL] = {
    --   [SensorMultilevel.REPORT] = sensor_multilevel_report_handler
    -- }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = added_handler
  },
  NAME = "Aeotec Door Window Sensor  8",
  can_handle = can_handle_aeotec_door_window_sensor_8
}

return aeotec_door_window_sensor_8