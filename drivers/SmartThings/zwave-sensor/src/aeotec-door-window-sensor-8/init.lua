-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 11 })

local utils = require "st.utils"

local TemperatureDefaults = require "st.zwave.defaults.temperatureMeasurement"
local HumidityDefaults = require "st.zwave.defaults.relativeHumidityMeasurement"
local DewPointDefaults = require "st.zwave.defaults.dewPoint"

local MoldHealthConcern = capabilities.moldHealthConcern
local ContactSensor = capabilities.contactSensor
local PowerSource = capabilities.powerSource
local ThreeAxis = capabilities.threeAxis
local TamperAlert = capabilities.tamperAlert

local ACCELERATION_VECTOR_FIELD = "accelerationVector"

local function added_handler(driver, device)
  device:emit_event(MoldHealthConcern.supportedMoldValues({"good", "unhealthy"}))

  -- Default value
  device:emit_event(MoldHealthConcern.moldHealthConcern.good())

  -- Default value
  device:emit_event(PowerSource.powerSource.battery())

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
      event = PowerSource.powerSource.dc()
    elseif cmd.args.event == Notification.event.power_management.POWER_HAS_BEEN_APPLIED then
      device:send(Battery:Get({}))
    end
  end

  -- MOLD
  if cmd.args.notification_type == Notification.notification_type.WEATHER_ALARM then
    if cmd.args.event == Notification.event.weather_alarm.STATE_IDLE then
      event = MoldHealthConcern.moldHealthConcern.good()
    elseif cmd.args.event == Notification.event.weather_alarm.MOISTURE_ALARM then
      event = MoldHealthConcern.moldHealthConcern.unhealthy()
    end
  end

  -- TAMPER
  if cmd.args.notification_type == Notification.notification_type.HOME_SECURITY then
    if cmd.args.event == Notification.event.home_security.STATE_IDLE then
      event = TamperAlert.tamper.clear()
    elseif cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED then
      event = TamperAlert.tamper.detected()
    end
  end

  if (event ~= nil) then
    device:emit_event(event)
  end
end

local function custom_three_axis_report_handler(self, device, cmd)
  local sensor_type = cmd.args.sensor_type
  local axis

  if sensor_type == SensorMultilevel.sensor_type.ACCELERATION_X_AXIS then
    axis = "X"
  elseif sensor_type == SensorMultilevel.sensor_type.ACCELERATION_Y_AXIS then
    axis = "Y"
  elseif sensor_type == SensorMultilevel.sensor_type.ACCELERATION_Z_AXIS then
    axis = "Z"
  else
    return
  end

  local value = cmd.args.sensor_value
  if value == nil then
    return
  end

  -- Z-Wave: m/s²; SmartThings threeAxis: mG
  local mg = utils.round(value / 9.81 * 1000)
  mg = math.max(-10000, math.min(10000, mg))

  local vector = device:get_field(ACCELERATION_VECTOR_FIELD) or {}
  vector[axis] = mg
  device:set_field(ACCELERATION_VECTOR_FIELD, vector, { persist = true })

  if vector.X ~= nil and vector.Y ~= nil and vector.Z ~= nil then
    device:emit_event(ThreeAxis.threeAxis({
      value = { vector.X, vector.Y, vector.Z },
      unit = "mG"
    }))
  end
end

local function sensor_multilevel_report_handler(self, device, cmd)
  local sensor_type = cmd.args.sensor_type

  if sensor_type == SensorMultilevel.sensor_type.TEMPERATURE then
    TemperatureDefaults.zwave_handlers[cc.SENSOR_MULTILEVEL][SensorMultilevel.REPORT](
      self, device, cmd
    )
  elseif sensor_type == SensorMultilevel.sensor_type.RELATIVE_HUMIDITY then
    HumidityDefaults.zwave_handlers[cc.SENSOR_MULTILEVEL][SensorMultilevel.REPORT](
      self, device, cmd
    )
  elseif sensor_type == SensorMultilevel.sensor_type.DEW_POINT then
    DewPointDefaults.zwave_handlers[cc.SENSOR_MULTILEVEL][SensorMultilevel.REPORT](
      self, device, cmd
    )
  elseif sensor_type == SensorMultilevel.sensor_type.ACCELERATION_X_AXIS
      or sensor_type == SensorMultilevel.sensor_type.ACCELERATION_Y_AXIS
      or sensor_type == SensorMultilevel.sensor_type.ACCELERATION_Z_AXIS then
    custom_three_axis_report_handler(self, device, cmd)
  end
end

local aeotec_door_window_sensor_8 = {
  supported_capabilities = {
    capabilities.powerSource
  },
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
    [cc.SENSOR_MULTILEVEL] = {
      [SensorMultilevel.REPORT] = sensor_multilevel_report_handler
    }
  },
  lifecycle_handlers = {
    added = added_handler
  },
  NAME = "Aeotec Door Window Sensor  8",
  can_handle = require("aeotec-door-window-sensor-8.can_handle"),
}

return aeotec_door_window_sensor_8
