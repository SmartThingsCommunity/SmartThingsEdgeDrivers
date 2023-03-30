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
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.SensorAlarm
local SensorAlarm = (require "st.zwave.CommandClass.SensorAlarm")({ version = 1 })
--- @type st.zwave.CommandClass.SensorBinary
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })

local preferences = require "preferences"
local configurations = require "configurations"

local FIBARO_MFR_ID = 0x010F
local FIBARO_FLOOD_PROD_TYPES = { 0x0000, 0x0B00 }

local function can_handle_fibaro_flood_sensor(opts, driver, device, ...)
  return device:id_match(FIBARO_MFR_ID, FIBARO_FLOOD_PROD_TYPES, nil)
end


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

local function sensor_multilevel_report_handler(self, device, cmd)
  if (cmd.args.sensor_type == SensorMultilevel.sensor_type.TEMPERATURE) then
    local scale = 'C'
    if (cmd.args.scale == SensorMultilevel.scale.temperature.FAHRENHEIT) then scale = 'F' end
    device:emit_event(capabilities.temperatureMeasurement.temperature({value = cmd.args.sensor_value, unit = scale}))
  end
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
    [cc.SENSOR_MULTILEVEL] = {
      [SensorMultilevel.REPORT] = sensor_multilevel_report_handler
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = can_handle_fibaro_flood_sensor
}

return fibaro_flood_sensor
