-- SinuxSoft (c) 2025
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local log = require "log"
local clusters = require "st.matter.clusters"
local utils = require "st.utils"

local RAC_DEVICE_TYPE_ID = 0x0072
local THERMOSTAT_DEVICE_TYPE_ID = 0x0301

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"

local THERMOSTAT_MODE_MAP = {
  [clusters.Thermostat.types.ThermostatSystemMode.OFF]  = capabilities.thermostatMode.thermostatMode.off,
  [clusters.Thermostat.types.ThermostatSystemMode.COOL] = capabilities.thermostatMode.thermostatMode.cool,
  [clusters.Thermostat.types.ThermostatSystemMode.HEAT] = capabilities.thermostatMode.thermostatMode.heat,
  [clusters.Thermostat.types.ThermostatSystemMode.AUTO] = capabilities.thermostatMode.thermostatMode.auto,
  [clusters.Thermostat.types.ThermostatSystemMode.FAN_ONLY] = capabilities.thermostatMode.thermostatMode.fanonly,
}

local function find_default_endpoint(device, cluster)
  local eps = device:get_endpoints(cluster)
  table.sort(eps)
  for _, v in ipairs(eps) do
    if v ~= 0 then
      return v
    end
  end
  log.warn(string.format("No endpoint found, using default %d", device.MATTER_DEFAULT_ENDPOINT))
  return device.MATTER_DEFAULT_ENDPOINT
end

local function component_to_endpoint(device, component_name, cluster_id)
  local component_to_endpoint_map = device:get_field(COMPONENT_TO_ENDPOINT_MAP)
  if component_to_endpoint_map ~= nil and component_to_endpoint_map[component_name] ~= nil then
    return component_to_endpoint_map[component_name]
  end
  if not cluster_id then return device.MATTER_DEFAULT_ENDPOINT end
  return find_default_endpoint(device, cluster_id)
end

local endpoint_to_component = function (device, endpoint_id)
  local component_to_endpoint_map = device:get_field(COMPONENT_TO_ENDPOINT_MAP)
  if component_to_endpoint_map ~= nil then
    for comp, ep in pairs(component_to_endpoint_map) do
      if ep == endpoint_id then
        return comp
      end
    end
  end
  return "main"
end

local function on_off_attr_handler(_, device, ib)
  device:emit_event_for_endpoint(ib.endpoint_id,
    ib.data.value and capabilities.switch.switch.on() or capabilities.switch.switch.off())
end

local function temperature_attr_handler_factory(cap_attr)
  return function(_, device, ib)
    if not ib or not ib.data or ib.data.value == nil then return end
    local c = ib.data.value / 100.0
    device:emit_event_for_endpoint(ib.endpoint_id, cap_attr({ value = c, unit = "C" }))
  end
end

local function system_mode_handler(_, device, ib)
  if not ib or not ib.data or ib.data.value == nil then return end
  local cap = capabilities.thermostatMode
  if device:supports_capability_by_id(cap.ID) then
    local ev = THERMOSTAT_MODE_MAP[ib.data.value]
    if ev then device:emit_event_for_endpoint(ib.endpoint_id, ev()) end
  end
end

local setpoint_limits = {
  MIN_HEAT = "__MIN_HEAT", MAX_HEAT = "__MAX_HEAT",
  MIN_COOL = "__MIN_COOL", MAX_COOL = "__MAX_COOL",
}

local function heat_limit_handler_factory(field_key)
  return function(_, device, ib)
    if ib.data.value == nil then return end
    device:set_field(field_key, (ib.data.value / 100.0))
    local min = device:get_field(setpoint_limits.MIN_HEAT)
    local max = device:get_field(setpoint_limits.MAX_HEAT)
    if min and max and min < max then
      device:emit_event_for_endpoint(ib.endpoint_id,
        capabilities.thermostatHeatingSetpoint.heatingSetpointRange({ value = { minimum = min, maximum = max, step = 1.0 }, unit = "C" }))
    end
  end
end

local function cool_limit_handler_factory(field_key)
  return function(_, device, ib)
    if ib.data.value == nil then return end
    device:set_field(field_key, (ib.data.value / 100.0))
    local min = device:get_field(setpoint_limits.MIN_COOL)
    local max = device:get_field(setpoint_limits.MAX_COOL)
    if min and max and min < max then
      device:emit_event_for_endpoint(ib.endpoint_id,
        capabilities.thermostatCoolingSetpoint.coolingSetpointRange({ value = { minimum = min, maximum = max, step = 1.0 }, unit = "C" }))
    end
  end
end

local function handle_switch_on(_, device, cmd)
  local ep = component_to_endpoint(device, cmd.component, clusters.OnOff.ID)
  device:send(clusters.OnOff.server.commands.On(device, ep))
end

local function handle_switch_off(_, device, cmd)
  local ep = component_to_endpoint(device, cmd.component, clusters.OnOff.ID)
  device:send(clusters.OnOff.server.commands.Off(device, ep))
end

local function set_thermostat_mode(_, device, cmd)
  local want = cmd.args.mode
  local mode_id
  for k, v in pairs(THERMOSTAT_MODE_MAP) do
    if v.NAME == want then mode_id = k; break end
  end
  if mode_id then
    local ep = component_to_endpoint(device, cmd.component, clusters.Thermostat.ID)
    device:send(clusters.Thermostat.attributes.SystemMode:write(device, ep, mode_id))
  end
end

local function set_setpoint(attr)
  return function(_, device, cmd)
    local c = cmd.args.setpoint
    local ep = component_to_endpoint(device, cmd.component, clusters.Thermostat.ID)
    device:send(attr:write(device, ep, utils.round(c * 100.0)))
  end
end

local function device_init(_, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:subscribe()
end

local function info_changed(driver, device, event, args)
  for _, attr in ipairs({
    clusters.OnOff.attributes.OnOff,
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
    clusters.Thermostat.attributes.SystemMode,
    clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
    clusters.Thermostat.attributes.AbsMinCoolSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit,
    clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
    clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit
  }) do
    device:add_subscribed_attribute(attr)
  end
  device:subscribe()
end

local function is_matter_thermostat(_, _, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == THERMOSTAT_DEVICE_TYPE_ID or dt.device_type_id == RAC_DEVICE_TYPE_ID then
        return true
      end
    end
  end
  return false
end

local thermostat_handler = {
  NAME = "Thermostat Handler",
  can_handle = is_matter_thermostat,
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed,
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.Thermostat.ID] = {
        [clusters.Thermostat.attributes.LocalTemperature.ID] = temperature_attr_handler_factory(capabilities.temperatureMeasurement.temperature),
        [clusters.Thermostat.attributes.OccupiedCoolingSetpoint.ID] = temperature_attr_handler_factory(capabilities.thermostatCoolingSetpoint.coolingSetpoint),
        [clusters.Thermostat.attributes.OccupiedHeatingSetpoint.ID] = temperature_attr_handler_factory(capabilities.thermostatHeatingSetpoint.heatingSetpoint),
        [clusters.Thermostat.attributes.SystemMode.ID] = system_mode_handler,
        [clusters.Thermostat.attributes.AbsMinHeatSetpointLimit.ID] = heat_limit_handler_factory(setpoint_limits.MIN_HEAT),
        [clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit.ID] = heat_limit_handler_factory(setpoint_limits.MAX_HEAT),
        [clusters.Thermostat.attributes.AbsMinCoolSetpointLimit.ID] = cool_limit_handler_factory(setpoint_limits.MIN_COOL),
        [clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit.ID] = cool_limit_handler_factory(setpoint_limits.MAX_COOL),
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temperature_attr_handler_factory(capabilities.temperatureMeasurement.temperature),
      }
    },
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = set_thermostat_mode,
      [capabilities.thermostatMode.commands.off.NAME] = function(d,dev,cmd) set_thermostat_mode(d,dev,{component=cmd.component,args={mode=capabilities.thermostatMode.thermostatMode.off.NAME}}) end,
      [capabilities.thermostatMode.commands.auto.NAME] = function(d,dev,cmd) set_thermostat_mode(d,dev,{component=cmd.component,args={mode=capabilities.thermostatMode.thermostatMode.auto.NAME}}) end,
      [capabilities.thermostatMode.commands.cool.NAME] = function(d,dev,cmd) set_thermostat_mode(d,dev,{component=cmd.component,args={mode=capabilities.thermostatMode.thermostatMode.cool.NAME}}) end,
      [capabilities.thermostatMode.commands.heat.NAME] = function(d,dev,cmd) set_thermostat_mode(d,dev,{component=cmd.component,args={mode=capabilities.thermostatMode.thermostatMode.heat.NAME}}) end,
      [capabilities.thermostatMode.commands.fanOnly and capabilities.thermostatMode.commands.fanOnly.NAME or "fanOnly"] =
        function(d,dev,cmd) set_thermostat_mode(d,dev,{component=cmd.component,args={mode=capabilities.thermostatMode.thermostatMode.fanonly.NAME}}) end,
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = set_setpoint(clusters.Thermostat.attributes.OccupiedCoolingSetpoint),
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_setpoint(clusters.Thermostat.attributes.OccupiedHeatingSetpoint),
    },
  },
  supported_capabilities = {
    capabilities.switch,
    capabilities.temperatureMeasurement,
    capabilities.thermostatMode,
    capabilities.thermostatCoolingSetpoint,
    capabilities.thermostatHeatingSetpoint,
  },
}

return thermostat_handler