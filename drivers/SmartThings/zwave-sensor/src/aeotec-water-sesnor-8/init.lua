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
--- @type st.zwave.CommandClass.SensorBinary
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })

local log = require "log"
local utils = require "st.utils"

local MoldHealthConcern = capabilities.moldHealthConcern

local AEOTEC_WATER_SENSOR_8_FINGERPRINTS = {
  { manufacturerId = 0x0371, productId = 0x0038 } -- Aeotec Water Sensor 8 EU/US/AU
}

local function can_handle_aeotec_water_sensor_8(opts, driver, device, ...)
  for _, fingerprint in ipairs(AEOTEC_WATER_SENSOR_8_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      local subdriver = require("aeotec-aerq")
      return true, subdriver
    end
  end
  return false
end

local function added_handler(driver, device)
  device:send(Configuration:Set({
    parameter_number = 22,
    size = 1,
    configuration_value = 1
  }))

  device:emit_event(MoldHealthConcern.supportedMoldValues({"good", "moderate"}))
  device:send(SensorBinary:Get({sensor_type = SensorBinary.sensor_type.GENERAL}))

  device:emit_event(capabilities.refresh.refresh())
end

local function do_refresh(driver, device)
  device:send(SensorBinary:Get({sensor_type = SensorBinary.sensor_type.GENERAL}))
  device:send(Battery:Get({}))
end

local function notification_report_handler(self, device, cmd)
  local event
  if cmd.args.notification_type == Notification.notification_type.POWER_MANAGEMENT then
    if cmd.args.event == Notification.event.power_management.AC_MAINS_DISCONNECTED then
      event = capabilities.powerSource.powerSource.battery()
    elseif cmd.args.event == Notification.event.power_management.AC_MAINS_RE_CONNECTED then
      event = capabilities.powerSource.powerSource.mains()
    elseif cmd.args.event == Notification.event.power_management.POWER_HAS_BEEN_APPLIED then
      device:send(Battery:Get({}))
    end
  end

  if cmd.args.notification_type == Notification.notification_type.WEATHER_ALARM then
    if cmd.args.event == Notification.event.weather_alarm.STATE_IDLE then
      event = capabilities.moldHealthConcern.moldHealthConcern.good()
    elseif cmd.args.event == Notification.event.weather_alarm.MOISTURE_ALARM then
      event = capabilities.moldHealthConcern.moldHealthConcern.moderate()
    end
  end

  if (event ~= nil) then
    device:emit_event(event)
  end
end

local function sensor_binary_report_handler(self, device, cmd)
  local sensorType = cmd.args.sensor_type
  local value = cmd.args.sensor_value
  local event

  if sensorType == SensorBinary.sensor_type.GENERAL then
    if value == SensorBinary.sensor_value.IDLE then
      event = capabilities.moldHealthConcern.moldHealthConcern.good()
    elseif value == SensorBinary.sensor_value.DETECTED_AN_EVENT then
      event = capabilities.moldHealthConcern.moldHealthConcern.moderate()
    end
  end

  if (event ~= nil) then
    device:emit_event(event)
  end
end

local aeotec_water_sensor_8 = {
  supported_capabilities = {
    capabilities.powerSource
  },
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
    [cc.SENSOR_BINARY] = {
      [SensorBinary.REPORT] = sensor_binary_report_handler
    },
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    added = added_handler,
  },
  NAME = "Aeotec Water Sesnor  8",
  can_handle = can_handle_aeotec_water_sensor_8
}

return aeotec_water_sensor_8