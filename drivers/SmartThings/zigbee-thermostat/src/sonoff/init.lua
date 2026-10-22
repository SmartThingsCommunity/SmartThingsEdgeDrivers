-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local generic_body = require "st.zigbee.generic_body"
local messages = require "st.zigbee.messages"
local zcl_messages = require "st.zigbee.zcl"
local zb_const = require "st.zigbee.constants"
local utils = require "st.utils"

local PowerConfiguration = clusters.PowerConfiguration
local Thermostat = clusters.Thermostat

local Battery = capabilities.battery
local Refresh = capabilities.refresh
local TemperatureMeasurement = capabilities.temperatureMeasurement
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint
local ThermostatMode = capabilities.thermostatMode

local SONOFF_CLUSTER = 0xFC11
local CHILD_LOCK_ATTR = 0x0000
local WORK_MODE_ATTR = 0x0018
local WORK_MODE_OFF = 0x01
local WORK_MODE_MANUAL = 0x03
local WORK_MODE_SCHEDULE = 0x04
local WORK_MODE_TEMP_MANUAL = 0x05

local DEFAULT_MIN_SETPOINT = 5
local DEFAULT_MAX_SETPOINT = 30
local SETPOINT_STEP = 0.5
local CHILD_LOCK_PREFERENCE = "childLock"
local BLUETOOTH_PAIRING_PREFERENCE = "enterBluetoothPairing"
local MIN_HEAT_SETPOINT_LIMIT_FIELD = "min_heat_setpoint_limit"
local MAX_HEAT_SETPOINT_LIMIT_FIELD = "max_heat_setpoint_limit"
local SUPPORTED_MODES = {
  ThermostatMode.thermostatMode.off.NAME,
  ThermostatMode.thermostatMode.heat.NAME,
  ThermostatMode.thermostatMode.auto.NAME,
}

local CONFIGURATIONS = {
  {
    cluster = Thermostat.ID,
    attribute = Thermostat.attributes.LocalTemperature.ID,
    minimum_interval = 10,
    maximum_interval = 300,
    data_type = Thermostat.attributes.LocalTemperature.base_type,
    reportable_change = 50,
  },
  {
    cluster = Thermostat.ID,
    attribute = Thermostat.attributes.OccupiedHeatingSetpoint.ID,
    minimum_interval = 1,
    maximum_interval = 600,
    data_type = Thermostat.attributes.OccupiedHeatingSetpoint.base_type,
    reportable_change = 50,
  },
  {
    cluster = Thermostat.ID,
    attribute = Thermostat.attributes.SystemMode.ID,
    minimum_interval = 1,
    maximum_interval = 600,
    data_type = Thermostat.attributes.SystemMode.base_type,
  },
  {
    cluster = Thermostat.ID,
    attribute = Thermostat.attributes.MinHeatSetpointLimit.ID,
    minimum_interval = 30,
    maximum_interval = 21600,
    data_type = Thermostat.attributes.MinHeatSetpointLimit.base_type,
    reportable_change = 50,
  },
  {
    cluster = Thermostat.ID,
    attribute = Thermostat.attributes.MaxHeatSetpointLimit.ID,
    minimum_interval = 30,
    maximum_interval = 21600,
    data_type = Thermostat.attributes.MaxHeatSetpointLimit.base_type,
    reportable_change = 50,
  },
}

local function get_setpoint_range(device)
  local reported_min = device:get_field(MIN_HEAT_SETPOINT_LIMIT_FIELD)
  local reported_max = device:get_field(MAX_HEAT_SETPOINT_LIMIT_FIELD)
  local min = reported_min and (reported_min / 100) or DEFAULT_MIN_SETPOINT
  local max = reported_max and (reported_max / 100) or DEFAULT_MAX_SETPOINT

  if min > max then
    min = DEFAULT_MIN_SETPOINT
    max = DEFAULT_MAX_SETPOINT
  end

  return min, max
end

local function emit_setpoint_range(device)
  local min, max = get_setpoint_range(device)
  device:emit_event(ThermostatHeatingSetpoint.heatingSetpointRange({
    value = {
      minimum = min,
      maximum = max,
      step = SETPOINT_STEP,
    },
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

local function command_argument(command, name)
  if command.args ~= nil and command.args[name] ~= nil then
    return command.args[name]
  end

  return command.named_args and command.named_args[name]
end

local function refresh(_, device)
  local attributes = {
    Thermostat.attributes.LocalTemperature,
    Thermostat.attributes.OccupiedHeatingSetpoint,
    Thermostat.attributes.SystemMode,
    PowerConfiguration.attributes.BatteryPercentageRemaining,
  }

  for _, attribute in ipairs(attributes) do
    device:send(attribute:read(device))
  end
end

local function configure(driver, device)
  device:configure()
  refresh(driver, device)
  device:send(Thermostat.attributes.MinHeatSetpointLimit:read(device))
  device:send(Thermostat.attributes.MaxHeatSetpointLimit:read(device))
end

local function added(_, device)
  emit_supported_modes(device)
  emit_setpoint_range(device)
end

local function init(driver, device)
  for _, configuration in ipairs(CONFIGURATIONS) do
    device:add_configured_attribute(configuration)
  end
  added(driver, device)
  refresh(driver, device)
end

local function info_changed(_, device, _, args)
  local old_preferences = args.old_st_store and args.old_st_store.preferences or {}
  local child_lock = device.preferences[CHILD_LOCK_PREFERENCE]
  if child_lock ~= nil and old_preferences[CHILD_LOCK_PREFERENCE] ~= child_lock then
    device:send(cluster_base.write_attribute(
      device,
      data_types.ClusterId(SONOFF_CLUSTER),
      data_types.AttributeId(CHILD_LOCK_ATTR),
      data_types.validate_or_build_type(tonumber(child_lock) == 1, data_types.Boolean, "payload")
    ))
  end

  local bluetooth_pairing = device.preferences[BLUETOOTH_PAIRING_PREFERENCE]
  if bluetooth_pairing == true and old_preferences[BLUETOOTH_PAIRING_PREFERENCE] ~= true then
    local zcl_header = zcl_messages.ZclHeader({
      cmd = data_types.ZCLCommandId(0x10),
    })
    zcl_header.frame_ctrl:set_cluster_specific()
    device:send(messages.ZigbeeMessageTx({
      address_header = messages.AddressHeader(
        zb_const.HUB.ADDR,
        zb_const.HUB.ENDPOINT,
        device:get_short_address(),
        device:get_endpoint(SONOFF_CLUSTER) or 1,
        zb_const.HA_PROFILE_ID,
        SONOFF_CLUSTER
      ),
      body = zcl_messages.ZclMessageBody({
        zcl_header = zcl_header,
        zcl_body = generic_body.GenericBody(string.char(0x03, 0x01, 0x01)),
      }),
    }))
  end
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

local function setpoint_limit_handler(field)
  return function(_, device, value)
    if value.value ~= 0x8000 and value.value ~= -32768 then
      device:set_field(field, value.value, { persist = true })
      emit_setpoint_range(device)
    end
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
  local setpoint = command_argument(command, "setpoint")
  if setpoint >= 40 then
    setpoint = utils.f_to_c(setpoint)
  end

  local min, max = get_setpoint_range(device)
  setpoint = utils.clamp_value(setpoint, min, max)
  -- The TRV-ZBT persists heating setpoints in 0.5 C increments.
  setpoint = math.floor((setpoint / SETPOINT_STEP) + 0.000001) * SETPOINT_STEP
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:write(device, utils.round(setpoint * 100)))
  device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({ value = setpoint, unit = "C" }))
end

local function set_mode(_, device, command)
  local mode_to_system_mode = {
    [ThermostatMode.thermostatMode.off.NAME] = Thermostat.attributes.SystemMode.OFF,
    [ThermostatMode.thermostatMode.heat.NAME] = Thermostat.attributes.SystemMode.HEAT,
    [ThermostatMode.thermostatMode.auto.NAME] = Thermostat.attributes.SystemMode.AUTO,
  }
  local mode = command_argument(command, "mode")
  local system_mode = mode_to_system_mode[mode]
  if system_mode == nil then
    return
  end

  device:send(Thermostat.attributes.SystemMode:write(device, system_mode))
  emit_mode(device, mode)
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
        [Thermostat.attributes.MinHeatSetpointLimit.ID] = setpoint_limit_handler(MIN_HEAT_SETPOINT_LIMIT_FIELD),
        [Thermostat.attributes.MaxHeatSetpointLimit.ID] = setpoint_limit_handler(MAX_HEAT_SETPOINT_LIMIT_FIELD),
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
    infoChanged = info_changed,
  },
  can_handle = require "sonoff.can_handle",
}

return sonoff
