-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.ThermostatSetpoint
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({version=3})
--- @type st.zwave.CommandClass.ThermostatOperatingState
local ThermostatOperatingState = (require "st.zwave.CommandClass.ThermostatOperatingState")({version=1})
--- @type st.zwave.CommandClass.ThermostatMode
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({version=3})
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({version=11})
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})
--- @type st.zwave.CommandClass.MultiChannelAssociation
local MultiChannelAssociation = (require "st.zwave.CommandClass.MultiChannelAssociation")({version=3})
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({version=2})
local utils = require "st.utils"
local constants = require "st.zwave.constants"

local PARAMETERS = require("heatit-ztrm6.preferences")

local CURRENT_THERMOSTAT_HEATING_MODE = "current_mode"
local CURRENT_SENSOR_CHANNEL = "current_channel"
local CURRENT_SENSOR_MODE = "current_sensor_mode"

local function setpoint_type_for_mode(mode)
  if mode == ThermostatMode.mode.ENERGY_SAVE_HEAT then
    return ThermostatSetpoint.setpoint_type.ENERGY_SAVE_HEATING
  elseif mode == ThermostatMode.mode.COOL then
    return ThermostatSetpoint.setpoint_type.COOLING_1
  end
  return ThermostatSetpoint.setpoint_type.HEATING_1
end

--- Determine the correct profile name based on sensor mode and floor-temp visibility.
--- @param sensor_mode number Configuration parameter 2 value (0-5)
--- @param show_floor_temp string|number The showFloorTemp preference value
--- @return string profile_name
local function get_profile_name(sensor_mode, show_floor_temp)
  local is_regulator = sensor_mode == 5
  local show_floor = show_floor_temp == "1" or show_floor_temp == 1
  if is_regulator and show_floor then
    return "heatit-ztrm6-thermostat-regulator-extra-temp"
  elseif is_regulator then
    return "heatit-ztrm6-thermostat-regulator"
  elseif show_floor then
    return "heatit-ztrm6-thermostat-extra-temp"
  else
    return "heatit-ztrm6-thermostat"
  end
end

--- Switch the device profile if it does not match the requested one.
--- @param device st.zwave.Device
--- @param profile_name string
local function switch_profile(device, profile_name)
  if device.profile and device.profile.id == profile_name then
    return
  end
  device:try_update_metadata({ profile = profile_name })
  device.thread:call_with_delay(2, function()
    device:refresh()
  end)
end

--- Map sensor mode parameter value to the Z-Wave endpoint used for the
--- selected sensor and the component name that represents it.
--- @param sensor_value number Configuration parameter 2 value
--- @return table {channel_sensor_value, component, extra_capability}
local function get_sensor_channel(sensor_value)
  -- 0 = F, 1 = A, 2 = AF, 3 = A2, 4 = A2F, 5 = Regulator
  local channel_and_component
  if sensor_value == 5 then
    channel_and_component = { channel_sensor_value = 2, component = "roomTemperature", extra_capability = "" }
  elseif sensor_value >= 3 then
    channel_and_component = { channel_sensor_value = 3, component = "roomTemperatureExternal", extra_capability = "" }
  elseif sensor_value >= 1 then
    channel_and_component = { channel_sensor_value = 2, component = "roomTemperature", extra_capability = "" }
  elseif sensor_value == 0 then
    channel_and_component = { channel_sensor_value = 4, component = "floorTemperature", extra_capability = "" }
  else
    channel_and_component = { channel_sensor_value = 2, component = "roomTemperature", extra_capability = "" }
  end
  if sensor_value == 2 or sensor_value == 4 then
    channel_and_component.extra_capability = "floorTemperature"
  end
  return channel_and_component
end

--- Persist the sensor channel derived from configuration parameter 2 and
--- request a fresh temperature reading from the corresponding endpoint.
local function save_current_sensor_channel(device, sensor_value)
  local i_sensor_value = tonumber(sensor_value)
  local channel_and_component = get_sensor_channel(i_sensor_value)
  device:set_field(CURRENT_SENSOR_CHANNEL, channel_and_component.channel_sensor_value, { persist = true })
  device:set_field(CURRENT_SENSOR_MODE, i_sensor_value, { persist = true })

  -- Switch to regulator profile when PWER mode (5) is active, otherwise back to normal
  local profile_name = get_profile_name(i_sensor_value, device.preferences.showFloorTemp)
  switch_profile(device, profile_name)

  device:send_to_component(SensorMultilevel:Get({}), channel_and_component.component)
end

--- Return the persisted sensor channel. If unknown, request parameter 2 from
--- the device so it will be available on the next report.
local function get_current_sensor_channel(device)
  local current_channel = device:get_field(CURRENT_SENSOR_CHANNEL)
  if current_channel == nil then
    current_channel = -1
    device:send(Configuration:Get({parameter_number = 2}))
  end
  return current_channel
end

local function temperature_report_handler(self, device, cmd)
  if (cmd.args.sensor_type == SensorMultilevel.sensor_type.TEMPERATURE) then
    local scale = 'C'
    if (cmd.args.scale == SensorMultilevel.scale.temperature.FAHRENHEIT) then scale = 'F' end

    if cmd.src_channel == get_current_sensor_channel(device) then
      device:emit_event(capabilities.temperatureMeasurement.temperature({value = cmd.args.sensor_value, unit = scale}))
    end

    -- Floor temperature report channel = 4. Update floorTemperature capability if it exists
    if (cmd.src_channel == 4 and (device.preferences.showFloorTemp == "1" or device.preferences.showFloorTemp == 1)
        and device.profile.components["floorTemperature"] ~= nil) then
        device:emit_event_for_endpoint(4, capabilities.temperatureMeasurement.temperature({value = cmd.args.sensor_value, unit = scale}))
    end
  end
end

local function setpoint_report_handler(self, device, cmd)
  local current_thermostat_heating_mode = device:get_field(CURRENT_THERMOSTAT_HEATING_MODE)
  if (current_thermostat_heating_mode == nil) then
    device:send(ThermostatMode:Get({}))
  elseif cmd.args.setpoint_type == setpoint_type_for_mode(current_thermostat_heating_mode) then
    device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = cmd.args.value, unit = "C"}))
  end
end

local function thermostat_mode_report_handler(self, device, cmd)
  local mode = cmd.args.mode
  local event = nil
  local current_thermostat_heating_mode = device:get_field(CURRENT_THERMOSTAT_HEATING_MODE)

  if (mode == ThermostatMode.mode.OFF) then
    event = capabilities.thermostatMode.thermostatMode.off()
  else
    if (mode == ThermostatMode.mode.HEAT) then
      event = capabilities.thermostatMode.thermostatMode.heat()
      current_thermostat_heating_mode = ThermostatMode.mode.HEAT
      device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}))
    elseif (mode == ThermostatMode.mode.ENERGY_SAVE_HEAT) then
      event = capabilities.thermostatMode.thermostatMode.eco()
      current_thermostat_heating_mode = ThermostatMode.mode.ENERGY_SAVE_HEAT
      device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.ENERGY_SAVE_HEATING}))
    elseif (mode == ThermostatMode.mode.COOL) then
      event = capabilities.thermostatMode.thermostatMode.cool()
      current_thermostat_heating_mode = ThermostatMode.mode.COOL
      device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1}))
    end
    device:set_field(CURRENT_THERMOSTAT_HEATING_MODE, current_thermostat_heating_mode)
  end
  if (event ~= nil) then
    device:emit_event(event)
  end
end

local function configuration_report_handler(self, device, cmd)
  -- Update OperatingState
  if (cmd.args.parameter_number == 2) then
    -- Sensor setting
    save_current_sensor_channel(device, cmd.args.configuration_value)
  elseif (cmd.args.parameter_number == 27) then
    local modes = {
      [0] = ThermostatMode.mode.OFF,
      [1] = ThermostatMode.mode.HEAT,
      [2] = ThermostatMode.mode.COOL,
      [3] = ThermostatMode.mode.ENERGY_SAVE_HEAT
    }
    local mode = modes[cmd.args.configuration_value]
    if mode ~= nil then
      thermostat_mode_report_handler(self, device, {args = {mode = mode}})
      device:send(ThermostatOperatingState:Get({}))
    end
  end
end

local function set_thermostat_mode(driver, device, command)
  local modes = capabilities.thermostatMode.thermostatMode
  local mode = command.args.mode
  local modeValue = nil
  if (mode == modes.off.NAME) then
    modeValue = ThermostatMode.mode.OFF
  elseif (mode == modes.heat.NAME) then
    modeValue = ThermostatMode.mode.HEAT
  elseif (mode == modes.eco.NAME) then
    modeValue = ThermostatMode.mode.ENERGY_SAVE_HEAT
  elseif (mode == modes.cool.NAME) then
    modeValue = ThermostatMode.mode.COOL
  elseif (mode == "energysaveheat" or mode == "energy save heat") then
    modeValue = ThermostatMode.mode.ENERGY_SAVE_HEAT
  end

  if (modeValue ~= nil) then
    if modeValue ~= ThermostatMode.mode.OFF then
      device:set_field(CURRENT_THERMOSTAT_HEATING_MODE, modeValue)
    end
    device:send(ThermostatMode:Set({mode = modeValue}))

    local follow_up_poll = function()
      device:refresh()
    end
    device.thread:call_with_delay(1, follow_up_poll)
  end
end

--- Z-TRM6 is a Celsius device; only convert if device explicitly reports Fahrenheit
local function convert_to_device_temp(command_temp, device_scale)
  if device_scale == ThermostatSetpoint.scale.FAHRENHEIT then
    command_temp = utils.c_to_f(command_temp)
  end
  -- Round to 1 decimal place to avoid integer overflow in Z-Wave serialization
  command_temp = math.floor(command_temp * 10 + 0.5) / 10
  return command_temp
end

local function set_setpoint_factory(setpoint_type)
  return function(driver, device, cmd)
    local scale = device:get_field(constants.TEMPERATURE_SCALE)
    local value = convert_to_device_temp(cmd.args.setpoint, scale)
    local current_mode = device:get_field(CURRENT_THERMOSTAT_HEATING_MODE)
    local current_setpoint_type = current_mode and setpoint_type_for_mode(current_mode) or setpoint_type

    if current_mode == nil then
      -- With no prior mode (for example after startup while OFF), use HEAT until the device reports its mode.
      device:set_field(CURRENT_THERMOSTAT_HEATING_MODE, ThermostatMode.mode.HEAT)
      device:send(ThermostatMode:Get({}))
    end
    device:send(ThermostatSetpoint:Set({value = value, setpoint_type = current_setpoint_type, size = 2}))

    local follow_up_poll = function()
      device:send(ThermostatSetpoint:Get({setpoint_type = current_setpoint_type}))
      device:send(SensorMultilevel:Get({}))
    end
    device.thread:call_with_delay(1, follow_up_poll)
  end
end

local function do_refresh(self, device)
  device:send(ThermostatMode:Get({}))
  device:send(ThermostatOperatingState:Get({}))

  device:send_to_component(SensorMultilevel:Get({}), "roomTemperature")
  device:send_to_component(SensorMultilevel:Get({}), "roomTemperatureExternal")
  device:send_to_component(SensorMultilevel:Get({}), "floorTemperature")

  -- fetch meter values
  device:send(Meter:Get({scale = Meter.scale.electric_meter.WATTS}))
  device:send(Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}))

  -- fetch correct setpoint
  local current_thermostat_heating_mode = device:get_field(CURRENT_THERMOSTAT_HEATING_MODE)

  if current_thermostat_heating_mode == nil or current_thermostat_heating_mode == ThermostatMode.mode.HEAT then
    device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}))
  elseif current_thermostat_heating_mode == ThermostatMode.mode.ENERGY_SAVE_HEAT then
    device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.ENERGY_SAVE_HEATING}))
  elseif current_thermostat_heating_mode == ThermostatMode.mode.COOL then
    device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1}))
  end
end

local function reset_energy_meter(driver, device, command)
  local component = command and command.component and command.component or "main"
  -- Send Meter:Reset to the device, then re-fetch the energy value after a short delay
  device:send_to_component(Meter:Reset({}), component)
  device.thread:call_with_delay(1.5, function()
    device:send_to_component(Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}), component)
  end)
  -- Optimistically emit 0 kWh so the UI updates immediately
  device:emit_event(capabilities.energyMeter.energy({value = 0, unit = "kWh"}))
end

--- Meter report handler.
--- When loadSize preference is > 0 (contactor mode), the device cannot measure
--- the external load and reports 0 W. Override the power reading with the
--- simulated load (loadSize * 100 W) when the thermostat is actively heating.
local PowerMeterDefaults = require "st.zwave.defaults.powerMeter"
local EnergyMeterDefaults = require "st.zwave.defaults.energyMeter"

local function meter_report_handler(driver, device, cmd)
  local load_size = tonumber(device.preferences.loadSize) or 0
  if load_size > 0 and cmd.args.scale == Meter.scale.electric_meter.WATTS then
    local op_state = device:get_latest_state(
      "main", capabilities.thermostatOperatingState.ID,
      capabilities.thermostatOperatingState.thermostatOperatingState.NAME
    )
    if op_state == "heating" then
      device:emit_event(capabilities.powerMeter.power({value = load_size * 100, unit = "W"}))
      return
    elseif op_state == "idle" then
      device:emit_event(capabilities.powerMeter.power({value = 0, unit = "W"}))
      return
    end
  end
  -- Fall through to default handlers for both power (W) and energy (kWh)
  if cmd.args.scale == Meter.scale.electric_meter.KILOWATT_HOURS then
    EnergyMeterDefaults.zwave_handlers[cc.METER][Meter.REPORT](driver, device, cmd)
  else
    PowerMeterDefaults.zwave_handlers[cc.METER][Meter.REPORT](driver, device, cmd)
  end
end

local function endpoint_to_component(device, endpoint)
  if endpoint == 2 then
    return "roomTemperature"
  elseif endpoint == 3 then
    return "roomTemperatureExternal"
  elseif endpoint == 4 then
    return "floorTemperature"
  end
  return "main"
end

local function component_to_endpoint(device, component_id)
  if component_id == "roomTemperature" then
    return {2}
  elseif component_id == "roomTemperatureExternal" then
    return {3}
  elseif component_id == "floorTemperature" then
    return {4}
  else
    return {}
  end
end

local function map_components(self, device)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local function do_added(self, device)
  -- Explicitly advertise supported modes so the platform sees "eco" instead of
  -- the default "energy save heat" that the Z-Wave SupportedReport handler produces.
  local supported_modes = {
    capabilities.thermostatMode.thermostatMode.off.NAME,
    capabilities.thermostatMode.thermostatMode.heat.NAME,
    capabilities.thermostatMode.thermostatMode.cool.NAME,
    capabilities.thermostatMode.thermostatMode.eco.NAME
  }
  device:emit_event(capabilities.thermostatMode.supportedThermostatModes(supported_modes, { visibility = { displayed = false } }))
  device:send(Meter:Get({scale = Meter.scale.electric_meter.WATTS}))
  device:send(Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}))
  device:refresh()
end

local function do_init(self, device)
  map_components(self, device)
end

--- Read and use associations from string.
--- Expected format: decimal NODEID or NODEID.ENDPOINT delimited by one or more spaces
local function get_node_ids_from_string(node_id_string)
  local assoc_nodes = {}
  local assoc_nodes_endpoints = {}
  if string.len(node_id_string) >= 1 then
    for node in string.gmatch(node_id_string, "%d+%.?%d*") do
      local dot_start = string.find(node, "%.")
      if dot_start == nil then
        table.insert(assoc_nodes, tonumber(node))
      else
        table.insert(assoc_nodes_endpoints, {
          multi_channel_node_id = tonumber(string.sub(node, 1, dot_start - 1)),
          end_point = tonumber(string.sub(node, dot_start + 1, dot_start + 3)),
          bit_address = false
        })
      end
    end
  end
  return assoc_nodes, assoc_nodes_endpoints
end

--- Handle changes to the association group preferences (parameter numbers >= 202).
--- Group id is the last two digits of the parameter number, e.g. 302 -> group 2.
local function info_changed_associations(driver, device, parameter_number, value)
  local assoc_nodes, assoc_nodes_endpoints = get_node_ids_from_string(value or "")
  local group_id = parameter_number - 300
  device:send(MultiChannelAssociation:Remove({grouping_identifier = group_id, node_ids = {}}))
  device:send(MultiChannelAssociation:Set({ grouping_identifier = group_id, node_ids = assoc_nodes, multi_channel_nodes = assoc_nodes_endpoints}))
  device:send(MultiChannelAssociation:Get({ grouping_identifier = group_id}))
end

--- Handle preference (Settings) changes from the SmartThings app.
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param event table
--- @param args table
local function info_changed(driver, device, event, args)
  for id, value in pairs(device.preferences) do
    local param = PARAMETERS[id]
    if param and args.old_st_store.preferences[id] ~= value then
      local new_parameter_value = tonumber(value)
      if new_parameter_value == nil then -- in case the value is boolean
        new_parameter_value = value and 1 or 0
      end
      local parameter_number = param.parameter_number

      if parameter_number > 400 then
        if parameter_number == 999 then
          device:send(ThermostatSetpoint:CapabilitiesGet({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}))
        elseif parameter_number == 901 then
          -- Determine profile based on both floor-temp toggle and current sensor mode
          local sensor_mode = tonumber(device:get_field(CURRENT_SENSOR_MODE) or device.preferences.sensorMode or 1)
          switch_profile(device, get_profile_name(sensor_mode, new_parameter_value))
        end
      elseif parameter_number >= 202 then
        info_changed_associations(driver, device, parameter_number, value)
      else
        if param.size == 2 and new_parameter_value >= 0x8000 then
          -- Configuration v1 writes signed integers; the same 16 bits represent the unsigned device value.
          new_parameter_value = new_parameter_value - 0x10000
        end
        device:send(Configuration:Set({parameter_number = parameter_number, size = param.size, configuration_value = new_parameter_value}))
        device:send(Configuration:Get({parameter_number = parameter_number}))

        if (id == "comfortSetpoint") then
          device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}))
        elseif id == "ecoSetpoint" then
          device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.ENERGY_SAVE_HEATING}))
        elseif id == "coolingSetpoint" then
          device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1}))
        elseif id == "loadSize" then
          device:send(Meter:Get({scale = Meter.scale.electric_meter.WATTS}))
        end
      end
    end
  end
end

local heatit_ztrm6_thermostat = {
  NAME = "Heatit Z-TRM6 thermostat",
  zwave_handlers = {
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report_handler
    },
    [cc.THERMOSTAT_MODE] = {
      [ThermostatMode.REPORT] = thermostat_mode_report_handler,
      [ThermostatMode.SUPPORTED_REPORT] = function(driver, device, cmd) end
    },
    [cc.THERMOSTAT_SETPOINT] = {
      [ThermostatSetpoint.REPORT] = setpoint_report_handler,
      [ThermostatSetpoint.SET] = setpoint_report_handler
    },
    [cc.SENSOR_MULTILEVEL] = {
      [SensorMultilevel.REPORT] = temperature_report_handler
    },
    [cc.METER] = {
      [Meter.REPORT] = meter_report_handler
    },
  },
  capability_handlers = {
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = set_thermostat_mode,
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_setpoint_factory(ThermostatSetpoint.setpoint_type.HEATING_1)
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [capabilities.energyMeter.ID] = {
      [capabilities.energyMeter.commands.resetEnergyMeter.NAME] = reset_energy_meter
    }
  },
  lifecycle_handlers = {
    init = do_init,
    added = do_added,
    infoChanged = info_changed,
  },
  can_handle = require("heatit-ztrm6.can_handle")
}

return heatit_ztrm6_thermostat
