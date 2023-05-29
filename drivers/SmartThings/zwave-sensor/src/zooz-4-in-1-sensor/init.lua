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
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
--- @type st.utils
local utils = require "st.utils"

local ZOOZ_4_IN_1_FINGERPRINTS = {
  { manufacturerId = 0x027A, productType = 0x2021, productId = 0x2101 }, -- Zooz 4-in-1 sensor
  { manufacturerId = 0x0109, productType = 0x2021, productId = 0x2101 }, -- ZP3111US 4-in-1 Motion
  { manufacturerId = 0x0060, productType = 0x0001, productId = 0x0004 } -- Everspring Immune Pet PIR Sensor SP815
}

--- Determine whether the passed device is zooz_4_in_1_sensor
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_zooz_4_in_1_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZOOZ_4_IN_1_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

--- Handler for notification report command class
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Notification.Report
local function notification_report_handler(self, device, cmd)
  local event
  if cmd.args.notification_type == Notification.notification_type.HOME_SECURITY then
    if cmd.args.event == Notification.event.home_security.MOTION_DETECTION then
      event = cmd.args.notification_status == 0 and capabilities.motionSensor.motion.inactive() or capabilities.motionSensor.motion.active()
    elseif cmd.args.event == Notification.event.home_security.STATE_IDLE then
      if #cmd.args.event_parameter >= 1 and string.byte(cmd.args.event_parameter, 1) == 8 then
        event = capabilities.motionSensor.motion.inactive()
      else
        event = capabilities.tamperAlert.tamper.clear()
      end
    end
  end
  if (event ~= nil) then
    device:emit_event(event)
  end
end

local function get_lux_from_percentage(percentage_value)
  local conversion_table = {
    {min = 1, max = 9.99, multiplier = 3.843},
    {min = 10, max = 19.99, multiplier = 5.231},
    {min = 20, max = 29.99, multiplier = 4.999},
    {min = 30, max = 39.99, multiplier = 4.981},
    {min = 40, max = 49.99, multiplier = 5.194},
    {min = 50, max = 59.99, multiplier = 6.016},
    {min = 60, max = 69.99, multiplier = 4.852},
    {min = 70, max = 79.99, multiplier = 4.836},
    {min = 80, max = 89.99, multiplier = 4.613},
    {min = 90, max = 100, multiplier = 4.5}
  }
  for _, tables in ipairs(conversion_table) do
    if percentage_value >= tables.min and percentage_value <= tables.max then
      return utils.round(percentage_value * tables.multiplier)
    end
  end
  return utils.round(percentage_value * 5.312)
end

--- Handler for sensor multilevel report command class
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.SensorMultilevel.Report
local function sensor_multilevel_report_handler(self, device, cmd)
  if cmd.args.sensor_type == SensorMultilevel.sensor_type.LUMINANCE then
    device:emit_event(capabilities.illuminanceMeasurement.illuminance({value = get_lux_from_percentage(cmd.args.sensor_value), unit = "lux"}))
  elseif cmd.args.sensor_type == SensorMultilevel.sensor_type.RELATIVE_HUMIDITY then
    device:emit_event(capabilities.relativeHumidityMeasurement.humidity({value = utils.round(cmd.args.sensor_value)}))
  elseif cmd.args.sensor_type == SensorMultilevel.sensor_type.TEMPERATURE then
    local scale = cmd.args.scale == SensorMultilevel.scale.temperature.FAHRENHEIT and 'F' or 'C'
    device:emit_event(capabilities.temperatureMeasurement.temperature({value = cmd.args.sensor_value, unit = scale}))
  end
end

local zooz_4_in_1_sensor = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
    [cc.SENSOR_MULTILEVEL] = {
      [SensorMultilevel.REPORT] = sensor_multilevel_report_handler
    }
  },
  NAME = "zooz 4 in 1 sensor",
  can_handle = can_handle_zooz_4_in_1_sensor
}

return zooz_4_in_1_sensor
