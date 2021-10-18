-- Copyright 2021 SmartThings
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
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 2 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 2 })
local preferencesMap = require "preferences"

local NOTIFICATIONS = 2
local TAMPERING_AND_EXCEEDING_THE_TEMPERATURE = 3
local ACOUSTIC_SIGNALS = 4
local EXCEEDING_THE_TEMPERATURE = 2

local FIBARO_CO_SENSORS_FINGERPRINTS = {
  { manufacturerId = 0x010F, productType = 0x1201, productId = 0x1000 }, -- Fibaro CO Sensor
  { manufacturerId = 0x010F, productType = 0x1201, productId = 0x1001 }  -- Fibaro CO Sensor
}

local function parameterNumberToParameterName(preferences,parameterNumber)
  for id, parameter in pairs(preferences) do
    if parameter.parameter_number == parameterNumber then
      return id
    end
  end
end


--- Determine whether the passed device is a Fibaro CO Sensor
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @return boolean true if the device is smoke co alarm
local function can_handle_fibaro_co_sensor(opts, driver, device, cmd, ...)
  for _, fingerprint in ipairs(FIBARO_CO_SENSORS_FINGERPRINTS) do
    if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function update_preferences(self, device, args)
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

local device_added = function(self, device)
  device:send(Alarm:Get({z_wave_alarm_type = Alarm.z_wave_alarm_type.CO}))
  device:send(Alarm:Get({z_wave_alarm_type = Alarm.z_wave_alarm_type.HEAT}))
  device:send(Alarm:Get({z_wave_alarm_type = Alarm.z_wave_alarm_type.BURGLAR}))
end

local do_configure = function(self, device)
  device:refresh()
  device:send(Configuration:Set({parameter_number = NOTIFICATIONS, configuration_value = TAMPERING_AND_EXCEEDING_THE_TEMPERATURE}))
  device:send(Configuration:Set({parameter_number = ACOUSTIC_SIGNALS, configuration_value = EXCEEDING_THE_TEMPERATURE}))
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

local function info_changed(self, device, event, args)
  if (device:is_cc_supported(cc.WAKE_UP)) then
    update_preferences(self, device, args)
  end
end

local fibaro_co_sensor = {
  NAME = "Fibaro CO sensor zw5",
  zwave_handlers = {
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
  can_handle = can_handle_fibaro_co_sensor
}

return fibaro_co_sensor
