-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.SensorAlarm
local SensorAlarm = (require "st.zwave.CommandClass.SensorAlarm")({ version = 1 })
--- @type st.zwave.CommandClass.SensorBinary
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
--- @type st.zwave.CommandClass.SensorMultilevel

local preferences = require "preferences"
local configurations = require "configurations"

local function basic_set_handler(self, device, cmd)
  local value = cmd.args.target_value and cmd.args.target_value or cmd.args.value
  device:emit_event(value == 0xFF and capabilities.waterSensor.water.wet() or capabilities.waterSensor.water.dry())
end

local function sensor_alarm_report_handler(self, device, cmd)
  if (cmd.args.sensor_type == SensorAlarm.sensor_type.WATER_LEAK_ALARM) then
    if (cmd.args.sensor_state == SensorAlarm.sensor_state.ALARM) then
      device:emit_event(capabilities.waterSensor.water.wet())
    elseif (cmd.args.sensor_state == SensorAlarm.sensor_state.NO_ALARM) then
      device:emit_event(capabilities.waterSensor.water.dry())
    end
  elseif (cmd.args.sensor_type == SensorAlarm.sensor_type.GENERAL_PURPOSE_ALARM or cmd.args.sensor_type == SensorAlarm.sensor_type.SMOKE_ALARM) then
    local event
    if (cmd.args.sensor_state == SensorAlarm.sensor_state.ALARM) then
      event = capabilities.tamperAlert.tamper.detected()
    elseif (cmd.args.sensor_state == SensorAlarm.sensor_state.NO_ALARM) then
      event = capabilities.tamperAlert.tamper.clear()
    end
    if event ~= nil then
      device:emit_event(event)

      -- Tamper events are not cleared by the device; we auto clear after 30 seconds.
      device.thread:call_with_delay(30, function(d)
        device:emit_event(capabilities.tamperAlert.tamper.clear())
      end)
    end
  end
end

local function sensor_binary_report_handler(self, device, cmd)
  local event = cmd.args.sensor_value == 0xFF and capabilities.waterSensor.water.wet() or capabilities.waterSensor.water.dry()
  device:emit_event(event)
end

local function do_configure(driver, device)
  configurations.initial_configuration(driver, device)
  -- The flood sensor can be hardwired, so update any preferences
  if not device:is_cc_supported(cc.WAKE_UP) then
    preferences.update_preferences(driver, device)
  end
end

local fibaro_flood_sensor = {
  NAME = "fibaro flood sensor",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = basic_set_handler
    },
    [cc.SENSOR_ALARM] = {
      [SensorAlarm.REPORT] = sensor_alarm_report_handler
    },
    [cc.SENSOR_BINARY] = {
      [SensorBinary.REPORT] = sensor_binary_report_handler
    },
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("fibaro-flood-sensor.can_handle"),
}

return fibaro_flood_sensor
