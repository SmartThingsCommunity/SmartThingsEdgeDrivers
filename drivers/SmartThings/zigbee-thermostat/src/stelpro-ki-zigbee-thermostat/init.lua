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

local device_management = require "st.zigbee.device_management"

local clusters = require "st.zigbee.zcl.clusters"
local utils = require "st.utils"
local data_types = require "st.zigbee.data_types"
local cluster_base = require "st.zigbee.cluster_base"

local Thermostat = clusters.Thermostat
local ThermostatSystemMode = Thermostat.attributes.SystemMode
local ThermostatUserInterfaceConfiguration = clusters.ThermostatUserInterfaceConfiguration

local capabilities = require "st.capabilities"
local ThermostatMode = capabilities.thermostatMode
local ThermostatOperatingState = capabilities.thermostatOperatingState
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint
local TemperatureMeasurement = capabilities.temperatureMeasurement
local TemperatureAlarm = capabilities.temperatureAlarm

local STELPRO_KI_ZIGBEE_THERMOSTAT_FINGERPRINTS = {
  { mfr = "Stelpro", model = "STZB402+" },
  { mfr = "Stelpro", model = "ST218" },
}

-- The Groovy DTH stored the raw Celsius values because it was responsible for converting
-- to Farenheit if the user's location necessitated. Right now the driver only operates
-- in Celsius, but we will keep the logic until we have a clear understanding.
local RAW_TEMP = "raw_temp"
local RAW_SETPOINT = "raw_setpoint"
local STORED_SYSTEM_MODE = "stored_system_mode"

local MFR_SETPOINT_MODE_ATTTRIBUTE = 0x401C
local MFG_CODE = 0x1185

local MIN_SETPOINT = 5
local MAX_SETPOINT = 30

local SUPPORTED_MODES = {
  ThermostatMode.thermostatMode.off.NAME,
  ThermostatMode.thermostatMode.heat.NAME,
  ThermostatMode.thermostatMode.eco.NAME
}

local THERMOSTAT_MODE_MAP = {
  [ThermostatSystemMode.OFF]               = ThermostatMode.thermostatMode.off,
  [ThermostatSystemMode.HEAT]              = ThermostatMode.thermostatMode.heat,
  [ThermostatSystemMode.EMERGENCY_HEATING] = ThermostatMode.thermostatMode.eco
}

local is_stelpro_ki_zigbee_thermostat = function(opts, driver, device)
  for _, fingerprint in ipairs(STELPRO_KI_ZIGBEE_THERMOSTAT_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

local function has_member(haystack, needle)
  for _, value in ipairs(haystack) do
    if (value == needle) then
      return true
    end
  end

  return false
end

-- Due to a bug in this model's firmware, sometimes we don't get
-- an updated operating state; so we need some special logic to verify the accuracy.
-- TODO: Add firmware version check when change versions are known
-- The logic between these two functions works as follows:
--   In temperature and heatingSetpoint events check to see if we might need to request
--   the current operating state and request it with handle_operating_state_bugfix.
--
--   In operatingState events validate the data we received from the thermostat with
--   the current environment, adjust as needed. If we had to make an adjustment, then ask
--   for the setpoint again just to make sure we didn't miss data somewhere.
--
-- There is a risk of false positives where we receive a new valid operating state before the
-- new setpoint, so we basically toss it. When we come to receiving the setpoint or temperature
-- (temperature roughly every minute) then we should catch the problem and request an update.
-- I think this is a little easier than outright managing the operating state ourselves.
-- All comparisons are made using the raw integer from the thermostat (unrounded Celsius decimal * 100)
-- that is stored in temperature and setpoint events.

-- Check if we should request the operating state, and request it if so
local function handle_operating_state_bugfix(driver, device)
  local operating_state = device:get_latest_state("main", ThermostatOperatingState.ID, ThermostatOperatingState.thermostatOperatingState.NAME)
  local raw_temperature = device:get_field(RAW_TEMP)
  local raw_setpoint = device:get_field(RAW_SETPOINT)

  if raw_setpoint ~= nil and raw_temperature ~= nil then
    if raw_setpoint <= raw_temperature then
      if operating_state ~= ThermostatOperatingState.thermostatOperatingState.idle.NAME then
        device:send(Thermostat.attributes.PIHeatingDemand:read(device))
      end
    else
      if operating_state ~= ThermostatOperatingState.thermostatOperatingState.heating.NAME then
        device:send(Thermostat.attributes.PIHeatingDemand:read(device))
      end
    end
  end
end

-- Given a raw temperature reading in Celsius return a converted temperature.
local function get_temperature(value)
  -- Currently we only operate in Celsius
  return value / 100
end

local function thermostat_local_temperature_handler(driver, device, value, zb_rx)
  local temperature = value.value
  local temp_scale = "C"

  if temperature == 0x7ffd then -- Freeze Alarm
    device:emit_event(TemperatureAlarm.temperatureAlarm.freeze())
  elseif temperature == 0x7fff then -- Overheat Alarm
    device:emit_event(TemperatureAlarm.temperatureAlarm.heat())
  elseif temperature == 0x8000 or temperature == -32768 then -- Invalid temperature
    -- Do nothing
  else
    if temperature > 0x8000 then -- Handle negative C (< 32F) readings
      temperature = -(utils.round(2 * (65536 - temperature)) / 2)
    end
    device:set_field(RAW_TEMP, temperature)

    temperature = get_temperature(temperature)

    -- Handle cases where we need to update the temperature alarm state given certain temperatures
    -- Account for a f/w bug where the freeze alarm doesn't trigger at 0C
    if temperature <= 0 then
      device:emit_event(TemperatureAlarm.temperatureAlarm.freeze())
    elseif temperature >= 50 then -- Overheat alarm doesn't trigger until 80C, but we'll start sending at 50C to match thermostat display
      device:emit_event(TemperatureAlarm.temperatureAlarm.heat())
    elseif device:get_latest_state("main", TemperatureAlarm.ID, TemperatureAlarm.temperatureAlarm.NAME) ~= TemperatureAlarm.temperatureAlarm.cleared.NAME then
      device:emit_event(TemperatureAlarm.temperatureAlarm.cleared())
    end

    handle_operating_state_bugfix(driver, device)

    device:emit_event(TemperatureMeasurement.temperature({value = temperature, unit = temp_scale}))
  end
end

local function thermostat_heating_setpoint_handler(driver, device, value, zb_rx)
  local setpoint = value.value
  local temp_scale = "C"

  --  We receive 0x8000 when the thermostat is off
  if setpoint ~= 0x8000 and setpoint ~= -32768 then
    device:set_field(RAW_SETPOINT, setpoint)

    handle_operating_state_bugfix(driver, device)

    device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({value = get_temperature(setpoint), unit = temp_scale}))
  end
end

local function thermostat_system_mode_handler(driver, device, value, zb_rx)
  local mode = THERMOSTAT_MODE_MAP[value.value].NAME

  -- If we receive an off here then we are off
  -- Else we will determine the real mode in the mfg specific packet so store this
  if mode == ThermostatMode.thermostatMode.off.NAME then
    device:emit_event(ThermostatMode.thermostatMode.off())
  else
    device:set_field(STORED_SYSTEM_MODE, mode)
    -- Sometimes we don't get the final decision, so ask for it just in case
    device:send(cluster_base.read_manufacturer_specific_attribute(device, Thermostat.ID, MFR_SETPOINT_MODE_ATTTRIBUTE, MFG_CODE))
  end
end

local function thermostat_heating_demand_handler(driver, device, value, zb_rx)
  local event
  local heating_demand_threshold = 10 -- A demand less than this is idle

  if value.value < heating_demand_threshold then
    event = ThermostatOperatingState.thermostatOperatingState.idle()
  else
    event = ThermostatOperatingState.thermostatOperatingState.heating()
  end

  -- This code is from validateOperatingStateBugfix in the Groovy DTH
  -- Given an operating state event, check its validity against the current environment
  local changed = false
  local raw_setpoint = device:get_field(RAW_SETPOINT)
  local raw_temperature = device:get_field(RAW_TEMP)
  local system_mode = device:get_latest_state("main", ThermostatMode.ID, ThermostatMode.thermostatMode.NAME)

  if raw_setpoint ~= nil and raw_temperature ~= nil then
    if raw_setpoint <= raw_temperature or system_mode == ThermostatMode.thermostatMode.off.NAME then
      event = ThermostatOperatingState.thermostatOperatingState.idle()
      changed = (value.value >= heating_demand_threshold) -- We were going to be heating, but now idle, so we want to make sure to refresh the heating setpoint
    else
      event = ThermostatOperatingState.thermostatOperatingState.heating()
      changed = (value.value < heating_demand_threshold) -- We were going to be idle, but now heating, so we want to make sure to refresh the heating setpoint
    end
  end

  if changed then
    device:send(Thermostat.attributes.OccupiedHeatingSetpoint:read(device))
  end

  device:emit_event(event)
end

local function mfr_setpoint_mode_handler(driver, device, value, zb_rx)
  local stored_system_mode = device:get_field(STORED_SYSTEM_MODE)

  -- If the storedSystemMode is heat, then we set the real mode here
  -- Otherwise, we just ignore this
  if stored_system_mode == nil or stored_system_mode == ThermostatMode.thermostatMode.heat.NAME then
    device:emit_event(THERMOSTAT_MODE_MAP[value.value]())
  end
end

local function set_heating_setpoint(driver, device, command)
  local value = command.args.setpoint

  if value >= 40 then -- we got a command in fahrenheit
    value = utils.f_to_c(value)
  end

  if value >= MIN_SETPOINT and value <= MAX_SETPOINT then
    device:send(Thermostat.attributes.OccupiedHeatingSetpoint:write(device, value * 100))
    device:send(Thermostat.attributes.OccupiedHeatingSetpoint:read(device))
    device:send(Thermostat.attributes.PIHeatingDemand:read(device))
  end
end

local function set_thermostat_mode(driver, device, mode)
  if has_member(SUPPORTED_MODES, mode) then
    local mode_number
    local setpoint_mode_number

    if mode == ThermostatMode.thermostatMode.heat.NAME then
      mode_number = ThermostatSystemMode.HEAT
      setpoint_mode_number = 0x04
    elseif mode == ThermostatMode.thermostatMode.eco.NAME then
      mode_number = ThermostatSystemMode.HEAT
      setpoint_mode_number = 0x05
    else
      mode_number = ThermostatSystemMode.OFF
      setpoint_mode_number = 0x00
    end

    device:send(Thermostat.attributes.SystemMode:write(device, mode_number))
    device:send(cluster_base.write_manufacturer_specific_attribute(device, Thermostat.ID, MFR_SETPOINT_MODE_ATTTRIBUTE, MFG_CODE, data_types.Enum8, setpoint_mode_number))

    device.thread:call_with_delay(2, function(d)
      device:send(Thermostat.attributes.SystemMode:read(device))
      device:send(cluster_base.read_manufacturer_specific_attribute(device, Thermostat.ID, MFR_SETPOINT_MODE_ATTTRIBUTE, MFG_CODE))
    end)
  else
    -- Generate something for the mobile client if it is calling us
    device:emit_event(ThermostatMode.thermostatMode(device:get_latest_state("main", ThermostatMode.ID, ThermostatMode.thermostatMode.NAME)))
  end
end

local function thermostat_mode_setter(mode_name)
  return function(driver, device, command) return set_thermostat_mode(driver, device, mode_name) end
end

local function handle_set_thermostat_mode_command(driver, device, command)
  return set_thermostat_mode(driver, device, command.args.mode)
end

local function do_refresh(self, device)
  local attributes = {
    Thermostat.attributes.LocalTemperature,
    Thermostat.attributes.OccupiedHeatingSetpoint,
    Thermostat.attributes.PIHeatingDemand,
    Thermostat.attributes.SystemMode,
    ThermostatUserInterfaceConfiguration.attributes.TemperatureDisplayMode,
    ThermostatUserInterfaceConfiguration.attributes.KeypadLockout
  }
  for _, attribute in pairs(attributes) do
    device:send(attribute:read(device))
  end
  device:send(cluster_base.read_manufacturer_specific_attribute(device, Thermostat.ID, MFR_SETPOINT_MODE_ATTTRIBUTE, MFG_CODE))
end

local function do_configure(self, device)
  device:send(device_management.build_bind_request(device, Thermostat.ID, self.environment_info.hub_zigbee_eui))
  device:send(Thermostat.attributes.LocalTemperature:configure_reporting(device, 10, 60, 50))
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(device, 1, 600, 50))
  device:send(Thermostat.attributes.SystemMode:configure_reporting(device, 1, 0, 1))
  device:send(Thermostat.attributes.PIHeatingDemand:configure_reporting(device, 1, 3600, 1))

  device:send(cluster_base.configure_reporting(device, data_types.ClusterId(Thermostat.ID), MFR_SETPOINT_MODE_ATTTRIBUTE, data_types.Enum8.ID, 1, 0, 1))

  device:send(ThermostatUserInterfaceConfiguration.attributes.TemperatureDisplayMode:configure_reporting(device, 1, 0, 1))
  device:send(ThermostatUserInterfaceConfiguration.attributes.KeypadLockout:configure_reporting(device, 1, 0, 1))

  do_refresh(self, device)
end

local function device_added(self, device)
  device:emit_event(ThermostatMode.supportedThermostatModes(SUPPORTED_MODES, { visibility = { displayed = false } }))
  -- device:emit_event(TemperatureAlarm.temperatureAlarm.cleared())
end

local stelpro_ki_zigbee_thermostat = {
  NAME = "stelpro ki zigbee thermostat",
  zigbee_handlers = {
    attr = {
      [Thermostat.ID] = {
        [Thermostat.attributes.LocalTemperature.ID] = thermostat_local_temperature_handler,
        [Thermostat.attributes.OccupiedHeatingSetpoint.ID] = thermostat_heating_setpoint_handler,
        [Thermostat.attributes.SystemMode.ID] = thermostat_system_mode_handler,
        [Thermostat.attributes.PIHeatingDemand.ID] = thermostat_heating_demand_handler,
        [MFR_SETPOINT_MODE_ATTTRIBUTE] = mfr_setpoint_mode_handler
      },
    }
  },
  capability_handlers = {
    [ThermostatHeatingSetpoint.ID] = {
      [ThermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_heating_setpoint
    },
    [ThermostatMode.ID] = {
      [ThermostatMode.commands.setThermostatMode.NAME] = handle_set_thermostat_mode_command,
      [ThermostatMode.commands.off.NAME] = thermostat_mode_setter(ThermostatMode.thermostatMode.off.NAME),
      [ThermostatMode.commands.heat.NAME] = thermostat_mode_setter(ThermostatMode.thermostatMode.heat.NAME)
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure
  },
  can_handle = is_stelpro_ki_zigbee_thermostat
}

return stelpro_ki_zigbee_thermostat
