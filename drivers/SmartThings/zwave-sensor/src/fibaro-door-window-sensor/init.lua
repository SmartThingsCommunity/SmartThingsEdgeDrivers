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

local cc = require "st.zwave.CommandClass"
local capabilities = require "st.capabilities"
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 2 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 2 })
local preferencesMap = require "preferences"

local FIBARO_DOOR_WINDOW_SENSOR_WAKEUP_INTERVAL = 21600 --seconds

local FIBARO_DOOR_WINDOW_SENSOR_FINGERPRINTS = {
  { manufacturerId = 0x010F, prod = 0x0700, productId = 0x1000 }, -- Fibaro Open/Closed Sensor (FGK-10x) / Europe
  { manufacturerId = 0x010F, prod = 0x0700, productId = 0x2000 }, -- Fibaro Open/Closed Sensor (FGK-10x) / NA
  { manufacturerId = 0x010F, prod = 0x0702, productId = 0x1000 }, -- Fibaro Open/Closed Sensor 2 (FGDW-002) / Europe
  { manufacturerId = 0x010F, prod = 0x0702, productId = 0x2000 }, -- Fibaro Open/Closed Sensor 2 (FGDW-002) / NA
  { manufacturerId = 0x010F, prod = 0x0702, productId = 0x3000 }, -- Fibaro Open/Closed Sensor 2 (FGDW-002) / ANZ
  { manufacturerId = 0x010F, prod = 0x0701, productId = 0x2001 }, -- Fibaro Open/Closed Sensor with temperature (FGK-10X) / NA
  { manufacturerId = 0x010F, prod = 0x0701, productId = 0x1001 }, -- Fibaro Open/Closed Sensor
  { manufacturerId = 0x010F, prod = 0x0501, productId = 0x1002 }  -- Fibaro Open/Closed Sensor
}

local function can_handle_fibaro_door_window_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(FIBARO_DOOR_WINDOW_SENSOR_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.prod, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function parameterNumberToParameterName(preferences,parameterNumber)
  for id, parameter in pairs(preferences) do
    if parameter.parameter_number == parameterNumber then
      return id
    end
  end
end

local function update_preferences(driver, device, args)
  local preferences = preferencesMap.get_device_parameters(device)
  for id, value in pairs(device.preferences) do
    local oldPreferenceValue = args.old_st_store.preferences[id]
    local newParameterValue = preferencesMap.to_numeric_value(device.preferences[id])
    local synchronized = device:get_field(id)
    if preferences and preferences[id] and (oldPreferenceValue ~= newParameterValue or synchronized == false) then
      device:send(Configuration:Set({parameter_number = preferences[id].parameter_number, size = preferences[id].size, configuration_value = newParameterValue}))
      device:set_field(id, false, {persist = true})
      device:send(Configuration:Get({parameter_number = preferences[id].parameter_number}))
    end
  end
  if args.old_st_store.preferences.reportingInterval ~= device.preferences.reportingInterval then
    device:send(WakeUp:IntervalSet({node_id = driver.environment_info.hub_zwave_id, seconds = device.preferences.reportingInterval * 3600}))
  end
end

local function configuration_report(driver, device, cmd)
  local preferences = preferencesMap.get_device_parameters(device)
  if preferences then
    local parameterName = parameterNumberToParameterName(preferences, cmd.args.parameter_number)
    local configValueSetByUser = device.preferences[parameterName]
    local configValueReportedByDevice = cmd.args.configuration_value
    if (parameterName and configValueSetByUser == configValueReportedByDevice) then
      device:set_field(parameterName, true, {persist = true})
    end
  end
end

local function device_added(self, device)
  device:refresh()
end

local function do_refresh(self, device)
  device:send(Battery:Get({}))
  if (device:supports_capability_by_id(capabilities.contactSensor.ID) and device:is_cc_supported(cc.SENSOR_BINARY)) then
    device:send(SensorBinary:Get({}))
  end
  if (device:supports_capability_by_id(capabilities.temperatureMeasurement.ID) and device:is_cc_supported(cc.SENSOR_MULTILEVEL )) then
    device:send(SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE}))
  end
end

local function do_configure(self, device)
  device:refresh()
  device:send(WakeUp:IntervalSet({node_id = self.environment_info.hub_zwave_id, seconds = FIBARO_DOOR_WINDOW_SENSOR_WAKEUP_INTERVAL}))
end

local function device_init(self, device)
  local preferences = preferencesMap.get_device_parameters(device)
  if preferences then
    device:set_update_preferences_fn(update_preferences)
    for id, _  in pairs(preferences) do
      device:set_field(id, true, {persist = true})
    end
  end
end

local function info_changed(driver, device, event, args)
end

local function notification_report_handler(self, device, cmd)
  local notificationType = cmd.args.notification_type
  local event = cmd.args.event

  if notificationType == Notification.notification_type.HOME_SECURITY then
    if event == Notification.event.home_security.STATE_IDLE then
      device:emit_event(capabilities.tamperAlert.tamper.clear())
    elseif event == Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED then
      device:emit_event(capabilities.tamperAlert.tamper.detected())
    end
  elseif notificationType == Notification.notification_type.ACCESS_CONTROL then
    if event == Notification.event.access_control.WINDOW_DOOR_IS_OPEN then
      device:emit_event(capabilities.contactSensor.contact.open())
    elseif event == Notification.event.access_control.WINDOW_DOOR_IS_CLOSED then
      device:emit_event(capabilities.contactSensor.contact.closed())
    end
  end
end

local fibaro_door_window_sensor = {
  NAME = "fibaro door window sensor",
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report
    }
  },
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
    init = device_init,
    infoChanged = info_changed
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  sub_drivers = {
    require("fibaro-door-window-sensor/fibaro-door-window-sensor-1"),
    require("fibaro-door-window-sensor/fibaro-door-window-sensor-2")
  },
  can_handle = can_handle_fibaro_door_window_sensor
}

return fibaro_door_window_sensor
