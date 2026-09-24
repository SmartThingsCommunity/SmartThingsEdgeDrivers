-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local cluster_base = require "st.zigbee.cluster_base"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local device_management = require "st.zigbee.device_management"
local generic_body = require "st.zigbee.generic_body"
local utils = require "st.utils"
local ZigbeeConstants = require "st.zigbee.constants"
local ZigbeeMessages = require "st.zigbee.messages"
local ZigbeeZcl = require "st.zigbee.zcl"

local Basic = clusters.Basic
local Thermostat = clusters.Thermostat
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint
local ThermostatMode = capabilities.thermostatMode
local ThermostatOperatingState = capabilities.thermostatOperatingState

local SONOFF_MFG_CODE = 0x1286
local SONOFF_PRIVATE_CLUSTER = 0xFC11
local TEMPORARY_MODE_COMMAND_ID = 0x11

local PRIVATE_ATTR_CHILD_LOCK = 0x0000
local PRIVATE_ATTR_BT_PAIRING_BROADCAST = 0x0029
local PRIVATE_ATTR_OPEN_WINDOW_DETECTION = 0x6000
local PRIVATE_ATTR_FROST_PROOF_TEMPERATURE = 0x6002
local PRIVATE_ATTR_TEMPERATURE_CONTROL_THRESHOLD = 0x601F
local PRIVATE_ATTR_RADAR_SENSITIVITY = 0x6020
local PRIVATE_ATTR_RADAR_DO_NOT_DISTURB = 0x6021
local PRIVATE_ATTR_RADAR_DO_NOT_DISTURB_PERIOD = 0x6022
local PRIVATE_ATTR_SCREEN_WORKING_BRIGHTNESS = 0x6023
local PRIVATE_ATTR_SCREEN_STANDBY_BRIGHTNESS = 0x6024
local PRIVATE_ATTR_SCREEN_NIGHT_STANDBY_BRIGHTNESS = 0x6025
local PRIVATE_ATTR_SCREEN_NIGHT_MODE = 0x6026
local PRIVATE_ATTR_SCREEN_NIGHT_PERIOD = 0x6027
local PRIVATE_ATTR_RELAY_OUTPUT_TYPE = 0x6028
local PRIVATE_ATTR_OVERHEAT_PROTECTION_TEMPERATURE = 0x6032
local PRIVATE_ATTR_OVERHEAT_PROTECTION = 0x6034
local PRIVATE_ATTR_RADAR_ENABLED = 0x6035

local THERMOSTAT_MODE_MAP = {
  [ThermostatMode.thermostatMode.off.NAME] = Thermostat.attributes.SystemMode.OFF,
  [ThermostatMode.thermostatMode.auto.NAME] = Thermostat.attributes.SystemMode.AUTO,
  [ThermostatMode.thermostatMode.heat.NAME] = Thermostat.attributes.SystemMode.HEAT,
}

local PRIVATE_PREFERENCES = {
  childLock = { attribute = PRIVATE_ATTR_CHILD_LOCK, data_type = data_types.Boolean },
  bluetoothPairingBroadcast = { attribute = PRIVATE_ATTR_BT_PAIRING_BROADCAST, data_type = data_types.Uint8 },
  openWindowDetection = { attribute = PRIVATE_ATTR_OPEN_WINDOW_DETECTION, data_type = data_types.Boolean },
  frostProofTemperature = { attribute = PRIVATE_ATTR_FROST_PROOF_TEMPERATURE, data_type = data_types.Int16, scale = 100 },
  radarSensitivity = { attribute = PRIVATE_ATTR_RADAR_SENSITIVITY, data_type = data_types.Uint8 },
  radarDoNotDisturb = { attribute = PRIVATE_ATTR_RADAR_DO_NOT_DISTURB, data_type = data_types.Boolean },
  screenWorkingBrightness = { attribute = PRIVATE_ATTR_SCREEN_WORKING_BRIGHTNESS, data_type = data_types.Uint8 },
  screenStandbyBrightness = { attribute = PRIVATE_ATTR_SCREEN_STANDBY_BRIGHTNESS, data_type = data_types.Uint8 },
  screenNightStandbyBrightness = { attribute = PRIVATE_ATTR_SCREEN_NIGHT_STANDBY_BRIGHTNESS, data_type = data_types.Uint8 },
  screenNightMode = { attribute = PRIVATE_ATTR_SCREEN_NIGHT_MODE, data_type = data_types.Boolean },
  overheatProtectionTemperature = { attribute = PRIVATE_ATTR_OVERHEAT_PROTECTION_TEMPERATURE, data_type = data_types.Int16, scale = 100 },
  overheatProtection = { attribute = PRIVATE_ATTR_OVERHEAT_PROTECTION, data_type = data_types.Boolean },
  radarEnabled = { attribute = PRIVATE_ATTR_RADAR_ENABLED, data_type = data_types.Boolean },
}

-- Builds a manufacturer-specific attribute write for the SONOFF private cluster.
local function write_private_attribute(device, attribute_id, data_type, value)
  -- The vendor cluster requires the eWeLink manufacturer code on every write.
  return cluster_base.write_manufacturer_specific_attribute(device, SONOFF_PRIVATE_CLUSTER, attribute_id, SONOFF_MFG_CODE, data_type, value)
end

-- Converts a preference value into the primitive expected by its Zigbee data type.
local function preference_value(value, preference)
  -- Boolean preferences are already represented as Lua booleans by the platform.
  if preference.data_type == data_types.Boolean then
    return value
  end
  local numeric_value = tonumber(value)
  if numeric_value == nil then
    return nil
  end
  return preference.scale and utils.round(numeric_value * preference.scale) or numeric_value
end

-- Restricts a clock value to the device's 30-minute schedule grid.
local function normalize_schedule_minutes(value)
  -- The device only accepts values from 00:00 through 23:30 at 30-minute intervals.
  local numeric_value = tonumber(value)
  if numeric_value == nil then
    return nil
  end
  return utils.clamp_value(math.floor((numeric_value + 15) / 30) * 30, 0, 1410)
end

-- Writes a paired start/end time preference as a typed Zigbee Structure.
local function write_schedule(device, attribute_id, start_value, end_value)
  -- Both schedule attributes are encoded symmetrically as two Uint16 structure members.
  local start_minutes = normalize_schedule_minutes(start_value)
  local end_minutes = normalize_schedule_minutes(end_value)
  if start_minutes == nil or end_minutes == nil then
    return
  end
  device:send(write_private_attribute(device, attribute_id, data_types.Structure, data_types.Structure({ data_types.Uint16(start_minutes), data_types.Uint16(end_minutes) })))
end

-- Sends the vendor temporary-mode command using the current preference values.
local function write_temporary_mode(device)
  -- Temporary mode is a cluster command rather than an attribute write.
  local action_byte = ({ exit = 0, boost = 1, timer = 2 })[device.preferences.temporaryModeAction]
  if action_byte == nil then
    return
  end
  local duration_seconds = math.floor(utils.clamp_value(tonumber(device.preferences.temporaryModeDuration) or 30, 1, 1440) * 60)
  local temperature = device.preferences.temporaryModeAction == "boost" and 30 or utils.clamp_value(tonumber(device.preferences.temporaryModeTemperature) or 30, 5, 30)
  local temperature_centi = utils.round(temperature * 100)
  local payload = string.char(action_byte, duration_seconds % 0x100, math.floor(duration_seconds / 0x100) % 0x100, math.floor(duration_seconds / 0x10000) % 0x100, math.floor(duration_seconds / 0x1000000) % 0x100, temperature_centi % 0x100, math.floor(temperature_centi / 0x100) % 0x100)
  local endpoint = device:get_endpoint(SONOFF_PRIVATE_CLUSTER) or device.fingerprinted_endpoint_id or 1
  local header = ZigbeeZcl.ZclHeader({ cmd = data_types.ZCLCommandId(TEMPORARY_MODE_COMMAND_ID) })
  header.frame_ctrl:set_cluster_specific()
  device:send(ZigbeeMessages.ZigbeeMessageTx({
    address_header = ZigbeeMessages.AddressHeader(ZigbeeConstants.HUB.ADDR, ZigbeeConstants.HUB.ENDPOINT, device:get_short_address(), endpoint, ZigbeeConstants.HA_PROFILE_ID, SONOFF_PRIVATE_CLUSTER),
    body = ZigbeeZcl.ZclMessageBody({ zcl_header = header, zcl_body = generic_body.GenericBody(payload) }),
  }))
end

-- Reads the standard attributes that back the supported SmartThings capabilities.
local function do_refresh(_, device)
  -- Private settings are changed through preferences and do not expose custom capability state.
  device:send(Thermostat.attributes.LocalTemperature:read(device))
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:read(device))
  device:send(Thermostat.attributes.SystemMode:read(device))
  device:send(Thermostat.attributes.ThermostatRunningState:read(device))
  device:send(Basic.attributes.SWBuildID:read(device))
end

-- Configures reporting for the standard thermostat attributes shown in the app.
local function do_configure(self, device)
  -- Binding and reporting keep the UI current without custom-cluster parsing.
  device:send(device_management.build_bind_request(device, Thermostat.ID, self.environment_info.hub_zigbee_eui))
  device:send(Thermostat.attributes.LocalTemperature:configure_reporting(device, 10, 300, 10))
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(device, 10, 300, 50))
  device:send(Thermostat.attributes.SystemMode:configure_reporting(device, 10, 300))
  device:send(Thermostat.attributes.ThermostatRunningState:configure_reporting(device, 10, 300, 1))
end

-- Applies preference changes to the matching standard or manufacturer-specific setting.
local function info_changed(_, device, _, args)
  -- Only changed preferences generate Zigbee traffic to avoid rewriting settings on unrelated updates.
  local old_preferences = args.old_st_store.preferences or {}
  for name, preference in pairs(PRIVATE_PREFERENCES) do
    local value = device.preferences[name]
    if value ~= nil and old_preferences[name] ~= value then
      local encoded_value = preference_value(value, preference)
      if encoded_value ~= nil then
        device:send(write_private_attribute(device, preference.attribute, preference.data_type, encoded_value))
      end
    end
  end
  if device.preferences.temperatureCompensation ~= old_preferences.temperatureCompensation then
    local compensation = tonumber(device.preferences.temperatureCompensation)
    if compensation ~= nil then
      device:send(Thermostat.attributes.LocalTemperatureCalibration:write(device, utils.round(compensation * 10)))
    end
  end
  if device.preferences.temperatureThresholdLow ~= old_preferences.temperatureThresholdLow or device.preferences.temperatureThresholdHigh ~= old_preferences.temperatureThresholdHigh then
    local low, high = tonumber(device.preferences.temperatureThresholdLow), tonumber(device.preferences.temperatureThresholdHigh)
    if low ~= nil and high ~= nil then
      device:send(write_private_attribute(device, PRIVATE_ATTR_TEMPERATURE_CONTROL_THRESHOLD, data_types.Structure, data_types.Structure({ data_types.Int16(utils.round(low * 100)), data_types.Int16(utils.round(high * 100)) })))
    end
  end
  if device.preferences.radarDoNotDisturbStart ~= old_preferences.radarDoNotDisturbStart or device.preferences.radarDoNotDisturbEnd ~= old_preferences.radarDoNotDisturbEnd then
    write_schedule(device, PRIVATE_ATTR_RADAR_DO_NOT_DISTURB_PERIOD, device.preferences.radarDoNotDisturbStart, device.preferences.radarDoNotDisturbEnd)
  end
  if device.preferences.screenNightStart ~= old_preferences.screenNightStart or device.preferences.screenNightEnd ~= old_preferences.screenNightEnd then
    write_schedule(device, PRIVATE_ATTR_SCREEN_NIGHT_PERIOD, device.preferences.screenNightStart, device.preferences.screenNightEnd)
  end
  if device.preferences.relayHeatingNormallyClosed ~= old_preferences.relayHeatingNormallyClosed or device.preferences.relayBoilerNormallyClosed ~= old_preferences.relayBoilerNormallyClosed then
    local relay_bitmap = (device.preferences.relayHeatingNormallyClosed and 1 or 0) + (device.preferences.relayBoilerNormallyClosed and 2 or 0)
    device:send(write_private_attribute(device, PRIVATE_ATTR_RELAY_OUTPUT_TYPE, data_types.Bitmap8, relay_bitmap))
  end
  if device.preferences.temporaryModeAction ~= old_preferences.temporaryModeAction then
    write_temporary_mode(device)
  end
end

-- Publishes the device software build identifier through the standard firmware capability.
local function software_build_id_handler(_, device, value)
  -- The framework decodes the String attribute before this handler is called.
  if type(value.value) == "string" and value.value ~= "" then
    device:emit_event(capabilities.firmwareUpdate.currentVersion({ value = value.value }))
  end
end

-- Converts the decoded local-temperature attribute from centi-degrees Celsius.
local function local_temperature_handler(_, device, value)
  -- Standard ZCL decoding provides the signed Int16 directly in value.value.
  device:emit_event(capabilities.temperatureMeasurement.temperature({ value = value.value / 100, unit = "C" }))
end

-- Converts the decoded occupied-heating-setpoint attribute from centi-degrees Celsius.
local function heating_setpoint_handler(_, device, value)
  -- The profile declares a single heating setpoint in Celsius.
  device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({ value = value.value / 100, unit = "C" }))
end

-- Maps the decoded SystemMode value to the supported SmartThings mode.
local function system_mode_handler(_, device, value)
  -- TP-WGZBA only exposes off, auto, and heat through the certified profile.
  local mode = ({ [Thermostat.attributes.SystemMode.OFF] = ThermostatMode.thermostatMode.off, [Thermostat.attributes.SystemMode.AUTO] = ThermostatMode.thermostatMode.auto, [Thermostat.attributes.SystemMode.HEAT] = ThermostatMode.thermostatMode.heat })[value.value]
  if mode ~= nil then
    device:emit_event(mode())
  end
end

-- Maps the decoded ThermostatRunningState bitmap to heating or idle.
local function running_state_handler(_, device, value)
  -- Any active running-state bit is represented as heating for this heating-only thermostat.
  device:emit_event(value.value == 0 and ThermostatOperatingState.thermostatOperatingState.idle() or ThermostatOperatingState.thermostatOperatingState.heating())
end

-- Writes a requested thermostat mode and reads it back after the device applies the change.
local function set_thermostat_mode(_, device, command)
  -- Delayed readback covers devices that do not report SystemMode changes.
  local mode = THERMOSTAT_MODE_MAP[command.args.mode]
  if mode == nil then
    return
  end
  device:send_to_component(command.component, Thermostat.attributes.SystemMode:write(device, mode))
  device.thread:call_with_delay(2, function()
    device:send_to_component(command.component, Thermostat.attributes.SystemMode:read(device))
  end)
end

-- Writes the requested heating setpoint using the thermostat cluster's centi-degree unit.
local function set_heating_setpoint(_, device, command)
  -- The driver accepts Fahrenheit app input and clamps all writes to the profile range.
  local value = command.args.setpoint
  if value >= 40 then
    value = utils.f_to_c(value)
  end
  device:send_to_component(command.component, Thermostat.attributes.OccupiedHeatingSetpoint:write(device, utils.round(utils.clamp_value(value, 5, 30) * 100)))
end

local sonoff_thermostat = {
  NAME = "SONOFF TP-WGZBA Thermostat Handler",
  can_handle = require "sonoff.can_handle",
  lifecycle_handlers = {
    added = function(driver, device)
      -- Publish the fixed mode set before the first standard-attribute refresh.
      device:emit_event(ThermostatMode.supportedThermostatModes({ "off", "auto", "heat" }, { visibility = { displayed = false } }))
      do_refresh(driver, device)
    end,
    driverSwitched = function(driver, device)
      -- Refresh state after the profile and handler have been replaced.
      device:emit_event(ThermostatMode.supportedThermostatModes({ "off", "auto", "heat" }, { visibility = { displayed = false } }))
      do_refresh(driver, device)
    end,
    doConfigure = do_configure,
    infoChanged = info_changed,
  },
  zigbee_handlers = {
    attr = {
      [Basic.ID] = { [Basic.attributes.SWBuildID.ID] = software_build_id_handler },
      [Thermostat.ID] = {
        [Thermostat.attributes.LocalTemperature.ID] = local_temperature_handler,
        [Thermostat.attributes.OccupiedHeatingSetpoint.ID] = heating_setpoint_handler,
        [Thermostat.attributes.SystemMode.ID] = system_mode_handler,
        [Thermostat.attributes.ThermostatRunningState.ID] = running_state_handler,
      },
    },
  },
  capability_handlers = {
    [capabilities.refresh.ID] = { [capabilities.refresh.commands.refresh.NAME] = do_refresh },
    [ThermostatMode.ID] = { [ThermostatMode.commands.setThermostatMode.NAME] = set_thermostat_mode },
    [ThermostatHeatingSetpoint.ID] = { [ThermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_heating_setpoint },
  },
}

return sonoff_thermostat
