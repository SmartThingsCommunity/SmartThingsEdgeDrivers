-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local device_management = require "st.zigbee.device_management"
local generic_body = require "st.zigbee.generic_body"
local messages = require "st.zigbee.messages"
local zcl_messages = require "st.zigbee.zcl"
local zb_const = require "st.zigbee.constants"
local utils = require "st.utils"

local PowerConfiguration = clusters.PowerConfiguration
local Thermostat = clusters.Thermostat

local Battery = capabilities.battery
local Momentary = capabilities.momentary
local Refresh = capabilities.refresh
local TemperatureMeasurement = capabilities.temperatureMeasurement
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint
local ThermostatMode = capabilities.thermostatMode

local SONOFF_CLUSTER = 0xFC11
local WORK_MODE_ATTR = 0x0018
local BUTTON_COMMAND = 0x10
local BLUETOOTH_PAIRING_START = 0x01

local WORK_MODE_OFF = 0x01
local WORK_MODE_MANUAL = 0x03
local WORK_MODE_SCHEDULE = 0x04
local WORK_MODE_TEMP_MANUAL = 0x05

local MIN_SETPOINT = 5
local MAX_SETPOINT = 30
local SUPPORTED_MODES = {
  ThermostatMode.thermostatMode.off.NAME,
  ThermostatMode.thermostatMode.heat.NAME,
  ThermostatMode.thermostatMode.auto.NAME,
}

local function emit_setpoint_range(device)
  device:emit_event(ThermostatHeatingSetpoint.heatingSetpointRange({
    value = { minimum = MIN_SETPOINT, maximum = MAX_SETPOINT },
    unit = "C",
  }, { visibility = { displayed = false } }))
end

local function emit_supported_modes(device)
  device:emit_event(ThermostatMode.supportedThermostatModes(SUPPORTED_MODES, {
    visibility = { displayed = false },
  }))
end

local function emit_mode(device, mode)
  device:emit_event(ThermostatMode.thermostatMode[mode]())
end

local function endpoint_for(device, cluster)
  return device:get_endpoint(cluster) or 1
end

local function send_bluetooth_pairing_start(device)
  local zcl_header = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(BUTTON_COMMAND),
  })
  zcl_header.frame_ctrl:set_cluster_specific()

  device:send(messages.ZigbeeMessageTx({
    address_header = messages.AddressHeader(
      zb_const.HUB.ADDR,
      zb_const.HUB.ENDPOINT,
      device:get_short_address(),
      endpoint_for(device, SONOFF_CLUSTER),
      zb_const.HA_PROFILE_ID,
      SONOFF_CLUSTER
    ),
    body = zcl_messages.ZclMessageBody({
      zcl_header = zcl_header,
      zcl_body = generic_body.GenericBody(string.char(0x03, 0x01, BLUETOOTH_PAIRING_START)),
    }),
  }))
end

local function refresh(_, device)
  local attributes = {
    Thermostat.attributes.LocalTemperature,
    Thermostat.attributes.OccupiedHeatingSetpoint,
    Thermostat.attributes.SystemMode,
    Thermostat.attributes.MinHeatSetpointLimit,
    Thermostat.attributes.MaxHeatSetpointLimit,
    PowerConfiguration.attributes.BatteryPercentageRemaining,
  }

  for _, attribute in ipairs(attributes) do
    device:send(attribute:read(device))
  end
end

local function configure(driver, device)
  local hub_eui = driver.environment_info.hub_zigbee_eui
  device:send(device_management.build_bind_request(device, Thermostat.ID, hub_eui))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, hub_eui))
  device:send(device_management.build_bind_request(device, SONOFF_CLUSTER, hub_eui))
  device:send(Thermostat.attributes.LocalTemperature:configure_reporting(device, 10, 300, 50))
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(device, 1, 600, 50))
  device:send(Thermostat.attributes.SystemMode:configure_reporting(device, 1, 600, 1))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30, 21600, 5))
  refresh(driver, device)
end

local function added(_, device)
  emit_supported_modes(device)
  emit_setpoint_range(device)
end

local function init(driver, device)
  added(driver, device)
  refresh(driver, device)
end

local function local_temperature_handler(_, device, value)
  if value.value ~= 0x8000 and value.value ~= -32768 then
    device:emit_event(TemperatureMeasurement.temperature({ value = value.value / 100, unit = "C" }))
  end
end

local function heating_setpoint_handler(_, device, value)
  if value.value ~= 0x8000 and value.value ~= -32768 then
    device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({ value = value.value / 100, unit = "C" }))
  end
end

local function system_mode_handler(_, device, value)
  if value.value == Thermostat.attributes.SystemMode.OFF then
    emit_mode(device, ThermostatMode.thermostatMode.off.NAME)
  elseif value.value == Thermostat.attributes.SystemMode.AUTO then
    emit_mode(device, ThermostatMode.thermostatMode.auto.NAME)
  elseif value.value == Thermostat.attributes.SystemMode.HEAT then
    emit_mode(device, ThermostatMode.thermostatMode.heat.NAME)
  end
end

local function battery_handler(_, device, value)
  device:emit_event(Battery.battery(utils.clamp_value(utils.round(value.value / 2), 0, 100)))
end

local function work_mode_handler(_, device, value)
  if value.value == WORK_MODE_OFF then
    emit_mode(device, ThermostatMode.thermostatMode.off.NAME)
  elseif value.value == WORK_MODE_SCHEDULE then
    emit_mode(device, ThermostatMode.thermostatMode.auto.NAME)
  elseif value.value == WORK_MODE_MANUAL or value.value == WORK_MODE_TEMP_MANUAL then
    emit_mode(device, ThermostatMode.thermostatMode.heat.NAME)
  end
end

local function set_heating_setpoint(_, device, command)
  local setpoint = command.args.setpoint
  if setpoint >= 40 then
    setpoint = utils.f_to_c(setpoint)
  end

  setpoint = utils.clamp_value(setpoint, MIN_SETPOINT, MAX_SETPOINT)
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:write(device, utils.round(setpoint * 100)))
  device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({ value = setpoint, unit = "C" }))
  device.thread:call_with_delay(1, function()
    device:send(Thermostat.attributes.OccupiedHeatingSetpoint:read(device))
  end)
end

local function set_mode(_, device, command)
  local mode_to_system_mode = {
    [ThermostatMode.thermostatMode.off.NAME] = Thermostat.attributes.SystemMode.OFF,
    [ThermostatMode.thermostatMode.heat.NAME] = Thermostat.attributes.SystemMode.HEAT,
    [ThermostatMode.thermostatMode.auto.NAME] = Thermostat.attributes.SystemMode.AUTO,
  }
  local system_mode = mode_to_system_mode[command.args.mode]
  if system_mode == nil then
    return
  end

  device:send(Thermostat.attributes.SystemMode:write(device, system_mode))
  emit_mode(device, command.args.mode)
  device.thread:call_with_delay(1, function()
    device:send(Thermostat.attributes.SystemMode:read(device))
  end)
end

local function mode_setter(mode)
  return function(driver, device, command)
    set_mode(driver, device, { args = { mode = mode } })
  end
end

local sonoff = {
  NAME = "SONOFF TRV-ZBT",
  capability_handlers = {
    [Refresh.ID] = {
      [Refresh.commands.refresh.NAME] = refresh,
    },
    [Momentary.ID] = {
      [Momentary.commands.push.NAME] = function(_, device)
        send_bluetooth_pairing_start(device)
      end,
    },
    [ThermostatHeatingSetpoint.ID] = {
      [ThermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_heating_setpoint,
    },
    [ThermostatMode.ID] = {
      [ThermostatMode.commands.setThermostatMode.NAME] = set_mode,
      [ThermostatMode.commands.off.NAME] = mode_setter(ThermostatMode.thermostatMode.off.NAME),
      [ThermostatMode.commands.heat.NAME] = mode_setter(ThermostatMode.thermostatMode.heat.NAME),
      [ThermostatMode.commands.auto.NAME] = mode_setter(ThermostatMode.thermostatMode.auto.NAME),
    },
  },
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_handler,
      },
      [Thermostat.ID] = {
        [Thermostat.attributes.LocalTemperature.ID] = local_temperature_handler,
        [Thermostat.attributes.OccupiedHeatingSetpoint.ID] = heating_setpoint_handler,
        [Thermostat.attributes.SystemMode.ID] = system_mode_handler,
      },
      [SONOFF_CLUSTER] = {
        [WORK_MODE_ATTR] = work_mode_handler,
      },
    },
  },
  lifecycle_handlers = {
    added = added,
    init = init,
    doConfigure = configure,
  },
  can_handle = require "sonoff.can_handle",
}

return sonoff
