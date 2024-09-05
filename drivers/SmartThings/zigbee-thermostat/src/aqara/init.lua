-- Copyright 2024 SmartThings
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
local data_types = require "st.zigbee.data_types"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local capabilities = require "st.capabilities"
local Thermostat = clusters.Thermostat
local PowerConfiguration = clusters.PowerConfiguration

local invisibleCapabilities = capabilities["stse.invisibleCapabilities"]
local valveCalibration = capabilities["stse.valveCalibration"]
local valveCalibrationCommandName = "startCalibration"

local PRIVATE_CLUSTER_ID = 0xFCC0
local MFG_CODE = 0x115F
local PRIVATE_VALVE_CALIBRATION_ID = 0x0270
local PRIVATE_VALVE_SWITCH_ATTRIBUTE_ID = 0x0271
local PRIVATE_THERMOSTAT_OPERATING_MODE_ATTRIBUTE_ID = 0x0272
local PRIVATE_THERM0STAT_VALVE_DETECTION_SWITCH_ID = 0x0274
local PRIVATE_THERMOSTAT_ALARM_INFORMATION_ID = 0x0275
local PRIVATE_CHILD_LOCK_ID = 0x0277
local PRIVATE_ANTIFREEZE_MODE_TEMPERATURE_SETTING_ID = 0x0279
local PRIVATE_VALVE_RESULT_CALIBRATION_ID = 0x027B
local PRIVATE_BATTERY_ENERGY_ID = 0x040A

local FINGERPRINTS = {
    { mfr = "LUMI", model = "lumi.airrtc.agl001" }
}

local preference_map = {
  ["stse.notificationOfValveTest"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = PRIVATE_THERM0STAT_VALVE_DETECTION_SWITCH_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Uint8,
    value_map = { [true] = 0x01,[false] = 0x00 },
  },
  ["stse.antifreezeModeSetting"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = PRIVATE_ANTIFREEZE_MODE_TEMPERATURE_SETTING_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Uint32,
  },
}

local function value_conversion(value)
  return tonumber(value)*50 + 450
end

local function device_info_changed(driver, device, event, args)
  local preferences = device.preferences
  local old_preferences = args.old_st_store.preferences
  if preferences ~= nil then
    for id, attr in pairs(preference_map) do
      local old_value = old_preferences[id]
      local value = preferences[id]
      if value ~= nil and value ~= old_value then
        if attr.value_map ~= nil then
          value = attr.value_map[value]
        end
        if preferences[id] == device.preferences["stse.antifreezeModeSetting"] then
          device:send(cluster_base.write_manufacturer_specific_attribute(device, attr.cluster_id, attr.attribute_id,
          attr.mfg_code, attr.data_type, value_conversion(value)))
        end
        if preferences[id] == device.preferences["stse.notificationOfValveTest"] then
          device:send(cluster_base.write_manufacturer_specific_attribute(device, attr.cluster_id, attr.attribute_id,
          attr.mfg_code, attr.data_type, value))
        end
      end
    end
  end
end

local function is_aqara_products(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function supported_thermostat_modes_handler(driver, device, value)
  device:emit_event(capabilities.thermostatMode.supportedThermostatModes({
    capabilities.thermostatMode.thermostatMode.manual.NAME,
    capabilities.thermostatMode.thermostatMode.antifreezing.NAME
  }, { visibility = { displayed = false } }))
end

local function do_refresh(driver, device)
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:read(device))
  device:send(cluster_base.read_manufacturer_specific_attribute(device,
  PRIVATE_CLUSTER_ID, PRIVATE_THERMOSTAT_OPERATING_MODE_ATTRIBUTE_ID, MFG_CODE))
  device:send(cluster_base.read_manufacturer_specific_attribute(device,
  PRIVATE_CLUSTER_ID, PRIVATE_VALVE_RESULT_CALIBRATION_ID, MFG_CODE))
end

local function device_init(driver, device)
  do_refresh(driver, device)
end

local function device_added(driver, device)
  supported_thermostat_modes_handler(driver, device, nil)
  device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 21.0, unit = "C"}))
  device:emit_event(capabilities.temperatureMeasurement.temperature({value = 27.0, unit = "C"}))
  device:emit_event(capabilities.thermostatMode.thermostatMode.manual())
  device:emit_event(capabilities.valve.valve.open())
  device:emit_component_event(device.profile.components.ChildLock, capabilities.lock.lock.unlocked())
  device:emit_event(capabilities.hardwareFault.hardwareFault.clear())
  device:emit_event(valveCalibration.calibrationState.calibrationPending())
  device:emit_event(invisibleCapabilities.invisibleCapabilities({""}))
  device:emit_event(capabilities.battery.battery(100))
end

local function thermostat_alarm_status_handler(driver, device, value, zb_rx)
  if value.value == 1 then
    device:emit_event(capabilities.hardwareFault.hardwareFault.detected())
  elseif value.value == 0 then
    device:emit_event(capabilities.hardwareFault.hardwareFault.clear())
  end
end

local function valve_calibration_status_handler(driver, device, value, zb_rx)
  if value.value == 0 then
    device:emit_event(valveCalibration.calibrationState.calibrationPending())
  elseif value.value == 1 then
    device:emit_event(valveCalibration.calibrationState.calibrationSuccess())
  elseif value.value == 2 then
    device:emit_event(valveCalibration.calibrationState.calibrationFailure())
  end
end

local function thermostat_operating_mode_status_handler(driver, device, value, zb_rx)
  if value.value == 0 or value.value == 3 then
    device:emit_event(capabilities.thermostatMode.thermostatMode.manual())
    device:emit_event(invisibleCapabilities.invisibleCapabilities({""}))
  elseif value.value == 2 then
    device:emit_event(capabilities.thermostatMode.thermostatMode.antifreezing())
    device:emit_event(invisibleCapabilities.invisibleCapabilities({"thermostatHeatingSetpoint"}))
  end
end

local function valve_status_handler(driver, device, value, zb_rx)
  local thermostat_mode = device:get_latest_state("main", capabilities.thermostatMode.ID,capabilities.thermostatMode.thermostatMode.NAME)

  if value.value == 1 then
    if thermostat_mode == 'manual' then
      device:emit_event(capabilities.valve.valve.open())
      device:emit_event(invisibleCapabilities.invisibleCapabilities({""}))
    elseif thermostat_mode == 'antifreezing' then
      device:emit_event(capabilities.valve.valve.open())
      device:emit_event(invisibleCapabilities.invisibleCapabilities({"thermostatHeatingSetpoint"}))
    end
  elseif value.value == 0 then
    device:emit_event(capabilities.valve.valve.closed())
    device:emit_event(invisibleCapabilities.invisibleCapabilities({"thermostatHeatingSetpoint","stse.valveCalibration","thermostatMode","lock"}))
  end
end

local function child_switch_status_handler(driver, device, value, zb_rx)
  if value.value == 1 then
    device:emit_component_event(device.profile.components.ChildLock, capabilities.lock.lock.locked())
  elseif value.value == 0 then
    device:emit_component_event(device.profile.components.ChildLock, capabilities.lock.lock.unlocked())
  end
end

local function thermostat_mode_attr_handler(driver, device, command)
  local set_mode = command.args.mode
  local pre_mode = device:get_latest_state("main", capabilities.thermostatMode.ID,capabilities.thermostatMode.thermostatMode.NAME)

  if pre_mode ~= set_mode then
    if set_mode == 'manual' then
      device:send(cluster_base.write_manufacturer_specific_attribute(device,
      PRIVATE_CLUSTER_ID, PRIVATE_THERMOSTAT_OPERATING_MODE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x00))
    elseif set_mode == 'antifreezing' then
      device:send(cluster_base.write_manufacturer_specific_attribute(device,
      PRIVATE_CLUSTER_ID, PRIVATE_THERMOSTAT_OPERATING_MODE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x02))
    end
  else
    if set_mode == 'manual' then
      device:emit_event(capabilities.thermostatMode.thermostatMode.manual())
    elseif set_mode == 'antifreezing' then
      device:emit_event(capabilities.thermostatMode.thermostatMode.antifreezing())
    end
  end
end

local function battery_energy_status_handler(driver, device, value, zb_rx)
  device:emit_event(capabilities.battery.battery(value.value))
end

local function open_heating_attr_handler(driver, device, command)
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_VALVE_SWITCH_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x01))
end

local function close_heating_attr_handler(driver, device, command)
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_VALVE_SWITCH_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x00))
end

local function valve_calibration_attr_handler(driver, device, command)
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_VALVE_CALIBRATION_ID, MFG_CODE, data_types.Uint8, 0x01))
end

local function child_switch_on_attr_handler(driver, device, command)
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_CHILD_LOCK_ID, MFG_CODE, data_types.Uint8, 0x01))
end

local function child_switch_off_attr_handler(driver, device, command)
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_CHILD_LOCK_ID, MFG_CODE, data_types.Uint8, 0x00))
end

local aqara_radiator_thermostat_e1_handler = {
  NAME = "Aqara Smart Radiator Thermostat E1 Handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = device_info_changed
  },
  zigbee_handlers = {
    attr = {
      [PRIVATE_CLUSTER_ID] = {
        [PRIVATE_THERMOSTAT_ALARM_INFORMATION_ID] = thermostat_alarm_status_handler,
        [PRIVATE_VALVE_RESULT_CALIBRATION_ID] = valve_calibration_status_handler,
        [PRIVATE_THERMOSTAT_OPERATING_MODE_ATTRIBUTE_ID] = thermostat_operating_mode_status_handler,
        [PRIVATE_VALVE_SWITCH_ATTRIBUTE_ID] = valve_status_handler,
        [PRIVATE_CHILD_LOCK_ID] = child_switch_status_handler,
        [PRIVATE_BATTERY_ENERGY_ID] = battery_energy_status_handler
      },
      [Thermostat.ID] = {
        [Thermostat.attributes.ControlSequenceOfOperation.ID] = supported_thermostat_modes_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = function() end,
        [PowerConfiguration.attributes.BatteryAlarmState.ID] = function() end
      }
    }
  },
  capability_handlers = {
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = thermostat_mode_attr_handler
    },
    [capabilities.valve.ID] = {
      [capabilities.valve.commands.open.NAME] = open_heating_attr_handler,
      [capabilities.valve.commands.close.NAME] = close_heating_attr_handler
    },
    [valveCalibration.ID] = {
      [valveCalibrationCommandName] = valve_calibration_attr_handler
    },
    [capabilities.lock.ID] = {
      [capabilities.lock.commands.lock.NAME] = child_switch_on_attr_handler,
      [capabilities.lock.commands.unlock.NAME] = child_switch_off_attr_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  can_handle = is_aqara_products
}

return aqara_radiator_thermostat_e1_handler