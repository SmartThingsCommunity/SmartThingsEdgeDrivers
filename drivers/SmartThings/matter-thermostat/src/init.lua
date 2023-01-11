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

local capabilities = require "st.capabilities"
local log = require "log"
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"

local MatterDriver = require "st.matter.driver"
local utils = require "st.utils"

local THERMOSTAT_MODE_MAP = {
  [clusters.Thermostat.types.ThermostatSystemMode.OFF]               = capabilities.thermostatMode.thermostatMode.off,
  [clusters.Thermostat.types.ThermostatSystemMode.AUTO]              = capabilities.thermostatMode.thermostatMode.auto,
  [clusters.Thermostat.types.ThermostatSystemMode.COOL]              = capabilities.thermostatMode.thermostatMode.cool,
  [clusters.Thermostat.types.ThermostatSystemMode.HEAT]              = capabilities.thermostatMode.thermostatMode.heat,
  [clusters.Thermostat.types.ThermostatSystemMode.EMERGENCY_HEATING] = capabilities.thermostatMode.thermostatMode.emergency_heat,
  [clusters.Thermostat.types.ThermostatSystemMode.FAN_ONLY]          = capabilities.thermostatMode.thermostatMode.fanOnly
}

local THERMOSTAT_OPERATING_MODE_MAP = {
  [0]		= capabilities.thermostatOperatingState.thermostatOperatingState.heating,
  [1]		= capabilities.thermostatOperatingState.thermostatOperatingState.cooling,
  [2]		= capabilities.thermostatOperatingState.thermostatOperatingState.fan_only,
}

local setpoint_limit_device_field = {
  MIN_HEAT = "MIN_HEAT",
  MAX_HEAT = "MAX_HEAT",
  MIN_COOL = "MIN_COOL",
  MAX_COOL = "MAX_COOL",
  MIN_DEADBAND = "MIN_DEADBAND",
}

local function device_init(driver, device)
  device:subscribe()
end

local function do_configure(driver, device)
  local heat_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.HEATING})
  local cool_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.COOLING})
  local auto_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.AUTOMODE})
  local thermo_eps = device:get_endpoints(clusters.Thermostat.ID)
  local fan_eps = device:get_endpoints(clusters.FanControl.ID)
  local humidity_eps = device:get_endpoints(clusters.RelativeHumidityMeasurement.ID)
  local profile_name = "thermostat"
  --Note: we have not encountered thermostats with multiple endpoints that support the Thermostat cluster
  if #thermo_eps == 1 then
    if #humidity_eps > 0 and #fan_eps > 0 then
      profile_name = profile_name .. "-humidity" .. "-fan"
    elseif #humidity_eps > 0 then
      profile_name = profile_name .. "-humidity"
    elseif #fan_eps > 0 then
      profile_name = profile_name .. "-fan"
    end

    if #heat_eps == 0 and #cool_eps == 0 then
      log.warn_with({hub_logs=true}, "Thermostat does not support heating or cooling. No matching profile")
      return
    elseif #heat_eps > 0 and #cool_eps == 0 then
      profile_name = profile_name .. "-heating-only"
    elseif #cool_eps > 0 and #heat_eps == 0 then
      profile_name = profile_name .. "-cooling-only"
    end

    -- TODO remove this in favor of reading Thermostat clusters AttributeList attribute
    -- to determine support for ThermostatRunningState
    profile_name = profile_name .. "-nostate"

    log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({profile = profile_name})
  else
    log.warn_with({hub_logs=true}, "Device does not support thermostat cluster")
  end

  --Query setpoint limits if needed
  local setpoint_limit_read = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  if #heat_eps ~= 0 and device:get_field(setpoint_limit_device_field.MIN_HEAT) == nil then
    setpoint_limit_read:merge(clusters.Thermostat.attributes.AbsMinHeatSetpointLimit:read())
  end
  if #heat_eps ~= 0 and device:get_field(setpoint_limit_device_field.MAX_HEAT) == nil then
    setpoint_limit_read:merge(clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit:read())
  end
  if #cool_eps ~= 0 and device:get_field(setpoint_limit_device_field.MIN_COOL) == nil then
    setpoint_limit_read:merge(clusters.Thermostat.attributes.AbsMinCoolSetpointLimit:read())
  end
  if #cool_eps ~= 0 and device:get_field(setpoint_limit_device_field.MAX_COOL) == nil then
    setpoint_limit_read:merge(clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit:read())
  end
  if #auto_eps ~= 0 and device:get_field(setpoint_limit_device_field.MIN_DEADBAND) == nil then
    setpoint_limit_read:merge(clusters.Thermostat.attributes.MinSetpointDeadBand:read())
  end
  if #setpoint_limit_read.info_blocks ~= 0 then
    device:send(setpoint_limit_read)
  end
end

local function device_added(driver, device)
  device:send(clusters.Thermostat.attributes.ControlSequenceOfOperation:read(device))
  device:send(clusters.FanControl.attributes.FanModeSequence:read(device))
end

local function temp_event_handler(attribute)
  return function(driver, device, ib, response)
    local temp = ib.data.value / 100.0
    local unit = "C"
    device:emit_event_for_endpoint(ib.endpoint_id, attribute({value = temp, unit = unit}))
  end
end

local function humidity_attr_handler(driver, device, ib, response)
  local humidity = math.floor(ib.data.value / 100.0)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(humidity))
end

local function system_mode_handler(driver, device, ib, response)
  if THERMOSTAT_MODE_MAP[ib.data.value] then
    device:emit_event_for_endpoint(ib.endpoint_id, THERMOSTAT_MODE_MAP[ib.data.value]())
    local supported_modes = device:get_latest_state(device:endpoint_to_component(ib.endpoint_id), capabilities.thermostatMode.ID, capabilities.thermostatMode.supportedThermostatModes.NAME) or {}
    -- TODO: remove -- this has been fixed upstream
    local sm = utils.deep_copy(supported_modes)
    -- if we get a mode report from the thermostat that isn't in the supported modes, then we need to update the supported modes
    for _, mode in ipairs(supported_modes) do
      if mode == THERMOSTAT_MODE_MAP[ib.data.value].NAME then
        return
      end
    end
    -- if we get here, then the reported mode was not in our mode map
    table.insert(sm, THERMOSTAT_MODE_MAP[ib.data.value].NAME)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatMode.supportedThermostatModes(sm))
  end
end

local function running_state_handler(driver, device, ib, response)
  for mode, operating_state in pairs(THERMOSTAT_OPERATING_MODE_MAP) do
    if ((ib.data.value >> mode) & 1) > 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, operating_state())
      return
    end
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatOperatingState.thermostatOperatingState.idle())
end

local function sequence_of_operation_handler(driver, device, ib, response)
  -- the values reported here are kind of limited in terms of our mapping, i.e. there's no way to know about whether
  -- or not the device supports emergency heat or fan only
  local supported_modes = {capabilities.thermostatMode.thermostatMode.off.NAME}
  if ib.data.value <= clusters.Thermostat.attributes.ControlSequenceOfOperation.COOLING_WITH_REHEAT then
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.cool.NAME)
  elseif ib.data.value <= clusters.Thermostat.attributes.ControlSequenceOfOperation.HEATING_WITH_REHEAT then
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.heat.NAME)
  elseif ib.data.value <= clusters.Thermostat.attributes.ControlSequenceOfOperation.COOLING_AND_HEATING_WITH_REHEAT then
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.cool.NAME)
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.heat.NAME)
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.auto.NAME) -- auto isn't _guaranteed_ by the spec
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatMode.supportedThermostatModes(supported_modes))
end

local function fan_mode_handler(driver, device, ib, response)
  if ib.data.value == clusters.FanControl.attributes.FanMode.AUTO or
    ib.data.value == clusters.FanControl.attributes.FanMode.SMART then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatFanMode.thermostatFanMode.auto())
  elseif ib.data.value == clusters.FanControl.attributes.FanMode.OFF then
    -- we don't have an "off" value
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatFanMode.thermostatFanMode.on())
  end
end

local function fan_mode_sequence_handler(driver, device, ib, response)
  -- Our thermostat fan mode control is probably not granular enough to handle the supported modes here well
  -- definitely meant for actual fans and not HVAC fans
  if ib.data.value >= clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO and
    ib.data.value <= clusters.FanControl.attributes.FanModeSequence.OFF_ON_AUTO then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatFanMode.supportedThermostatFanModes(
      {capabilities.thermostatFanMode.thermostatFanMode.auto.NAME, capabilities.thermostatFanMode.thermostatFanMode.on.NAME}))
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatFanMode.supportedThermostatFanModes(
      {capabilities.thermostatFanMode.thermostatFanMode.on.NAME}))
  end
end

local function set_thermostat_mode(driver, device, cmd)
  local mode_id = nil
  for value, mode in pairs(THERMOSTAT_MODE_MAP) do
    if mode.NAME == cmd.args.mode then
      mode_id = value
      break
    end
  end
  if mode_id then
    device:send(clusters.Thermostat.attributes.SystemMode:write(device, device:component_to_endpoint(cmd.component), mode_id))
  end
end

local thermostat_mode_setter = function(mode_name)
  return function(driver, device, cmd)
    return set_thermostat_mode(driver, device, {component = cmd.component, args = {mode = mode_name}})
  end
end

local function set_thermostat_fan_mode(driver, device, cmd)
  local fan_mode_id = nil
  if cmd.args.mode == capabilities.thermostatFanMode.thermostatFanMode.auto.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.AUTO
  elseif cmd.args.mode == capabilities.thermostatFanMode.thermostatFanMode.on.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.ON
  end
  if fan_mode_id then
    device:send(clusters.FanControl.attributes.FanMode:write(device, device:component_to_endpoint(cmd.component), fan_mode_id))
  end
end

local function thermostat_fan_mode_setter(mode_name)
  return function(driver, device, cmd)
    return set_thermostat_fan_mode(driver, device, {component = cmd.component, args = {mode = mode_name}})
  end
end

local function set_setpoint(setpoint)
  return function(driver, device, cmd)
    local value = cmd.args.setpoint
    if (value >= 40) then -- assume this is a fahrenheit value
      value = utils.f_to_c(value)
    end

    -- Gather cached setpoint values when considering setpoint limits
    -- Note: cached values should always exist, but defaults are chosen just in case to prevent
    -- nil operation errors, and deadband logic from triggering.
    local cached_cooling_val, cooling_setpoint = device:get_latest_state(
      cmd.component, capabilities.thermostatCoolingSetpoint.ID,
      capabilities.thermostatCoolingSetpoint.coolingSetpoint.NAME,
      100, { value = 100, unit = "C" }
    )
    if cooling_setpoint and cooling_setpoint.unit == "F" then
      cached_cooling_val = utils.f_to_c(cached_cooling_val)
    end
    local cached_heating_val, heating_setpoint = device:get_latest_state(
      cmd.component, capabilities.thermostatHeatingSetpoint.ID,
      capabilities.thermostatHeatingSetpoint.heatingSetpoint.NAME,
      0, { value = 0, unit = "C" }
    )
    if heating_setpoint and heating_setpoint.unit == "F" then
      cached_heating_val = utils.f_to_c(cached_heating_val)
    end
    local is_auto_capable = #device:get_endpoints(
      clusters.Thermostat.ID,
      {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.AUTOMODE}
    ) > 0

    --Check setpoint limits for the device
    local setpoint_type = string.match(setpoint.NAME, "Heat") or "Cool"
    local deadband = device:get_field(setpoint_limit_device_field.MIN_DEADBAND) or 2.5 --spec default
    if setpoint_type == "Heat" then
      local min = device:get_field(setpoint_limit_device_field.MIN_HEAT) or 0
      local max = device:get_field(setpoint_limit_device_field.MAX_HEAT) or 100
      if value < min or value > max then
        log.warn(string.format(
          "Invalid setpoint (%s) outside the min (%s) and the max (%s)",
          value, min, max
        ))
        device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint(heating_setpoint))
        return
      end
      if is_auto_capable and value > (cached_cooling_val - deadband) then
        log.warn(string.format(
          "Invalid setpoint (%s) is greater than the cooling setpoint (%s) with the deadband (%s)",
          value, cooling_setpoint, deadband
        ))
        device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint(heating_setpoint))
        return
      end
    else
      local min = device:get_field(setpoint_limit_device_field.MIN_COOL) or 0
      local max = device:get_field(setpoint_limit_device_field.MAX_COOL) or 100
      if value < min or value > max then
        log.warn(string.format(
          "Invalid setpoint (%s) outside the min (%s) and the max (%s)",
          value, min, max
        ))
        device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint(cooling_setpoint))
        return
      end
      if is_auto_capable and value < (cached_heating_val + deadband) then
        log.warn(string.format(
          "Invalid setpoint (%s) is less than the heating setpoint (%s) with the deadband (%s)",
          value, heating_setpoint, deadband
        ))
        device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint(cooling_setpoint))
        return
      end
    end
    device:send(setpoint:write(device, device:component_to_endpoint(cmd.component), utils.round(value * 100.0)))
  end
end

local function setpoint_limit_handler(limit_field)
  return function(driver, device, ib, response)
    local val = ib.data.value / 100.0
    log.info("Setting " .. limit_field .. " to " .. string.format("%s", val))
    device:set_field(limit_field, val, { persist = true })
  end
end

local function min_deadband_limit_handler(driver, device, ib, response)
  local val = ib.data.value / 10.0
  log.info("Setting " .. setpoint_limit_device_field.MIN_DEADBAND .. " to " .. string.format("%s", val))
  device:set_field(setpoint_limit_device_field.MIN_DEADBAND, val, { persist = true })
end

local function battery_percent_remaining_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
  },
  matter_handlers = {
    attr = {
      [clusters.Thermostat.ID] = {
        [clusters.Thermostat.attributes.LocalTemperature.ID] = temp_event_handler(capabilities.temperatureMeasurement.temperature),
        [clusters.Thermostat.attributes.OccupiedCoolingSetpoint.ID] = temp_event_handler(capabilities.thermostatCoolingSetpoint.coolingSetpoint),
        [clusters.Thermostat.attributes.OccupiedHeatingSetpoint.ID] = temp_event_handler(capabilities.thermostatHeatingSetpoint.heatingSetpoint),
        [clusters.Thermostat.attributes.SystemMode.ID] = system_mode_handler,
        [clusters.Thermostat.attributes.ThermostatRunningState.ID] = running_state_handler,
        [clusters.Thermostat.attributes.ControlSequenceOfOperation.ID] = sequence_of_operation_handler,
        [clusters.Thermostat.attributes.AbsMinHeatSetpointLimit.ID] = setpoint_limit_handler(setpoint_limit_device_field.MIN_HEAT),
        [clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit.ID] = setpoint_limit_handler(setpoint_limit_device_field.MAX_HEAT),
        [clusters.Thermostat.attributes.AbsMinCoolSetpointLimit.ID] = setpoint_limit_handler(setpoint_limit_device_field.MIN_COOL),
        [clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit.ID] = setpoint_limit_handler(setpoint_limit_device_field.MAX_COOL),
        [clusters.Thermostat.attributes.MinSetpointDeadBand.ID] = min_deadband_limit_handler,
      },
      [clusters.FanControl.ID] = {
        [clusters.FanControl.attributes.FanModeSequence.ID] = fan_mode_sequence_handler,
        [clusters.FanControl.attributes.FanMode.ID] = fan_mode_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler(capabilities.temperatureMeasurement.temperature),
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = humidity_attr_handler
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = battery_percent_remaining_attr_handler
      }
    }
  },
  subscribed_attributes = {
    [capabilities.temperatureMeasurement.ID] = {
      clusters.Thermostat.attributes.LocalTemperature,
      clusters.TemperatureMeasurement.attributes.MeasuredValue
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.thermostatMode.ID] = {
      clusters.Thermostat.attributes.SystemMode,
      clusters.Thermostat.attributes.ControlSequenceOfOperation
    },
    [capabilities.thermostatOperatingState.ID] = {
      clusters.Thermostat.attributes.ThermostatRunningState
    },
    [capabilities.thermostatFanMode.ID] = {
      clusters.FanControl.attributes.FanModeSequence,
      clusters.FanControl.attributes.FanMode
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      clusters.Thermostat.attributes.OccupiedCoolingSetpoint
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      clusters.Thermostat.attributes.OccupiedHeatingSetpoint
    },
    [capabilities.battery.ID] = {
      clusters.PowerSource.attributes.BatPercentRemaining
    }
  },
  capability_handlers = {
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = set_thermostat_mode,
      [capabilities.thermostatMode.commands.auto.NAME] = thermostat_mode_setter(capabilities.thermostatMode.thermostatMode.auto.NAME),
      [capabilities.thermostatMode.commands.off.NAME] = thermostat_mode_setter(capabilities.thermostatMode.thermostatMode.off.NAME),
      [capabilities.thermostatMode.commands.cool.NAME] = thermostat_mode_setter(capabilities.thermostatMode.thermostatMode.cool.NAME),
      [capabilities.thermostatMode.commands.heat.NAME] = thermostat_mode_setter(capabilities.thermostatMode.thermostatMode.heat.NAME),
      [capabilities.thermostatMode.commands.emergencyHeat.NAME] = thermostat_mode_setter(capabilities.thermostatMode.thermostatMode.emergency_heat.NAME)
    },
    [capabilities.thermostatFanMode.ID] = {
      [capabilities.thermostatFanMode.commands.setThermostatFanMode.NAME] = set_thermostat_fan_mode,
      [capabilities.thermostatFanMode.commands.fanAuto.NAME] = thermostat_fan_mode_setter(capabilities.thermostatFanMode.thermostatFanMode.auto.NAME),
      [capabilities.thermostatFanMode.commands.fanOn.NAME] = thermostat_fan_mode_setter(capabilities.thermostatFanMode.thermostatFanMode.on.NAME)
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = set_setpoint(clusters.Thermostat.attributes.OccupiedCoolingSetpoint)
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_setpoint(clusters.Thermostat.attributes.OccupiedHeatingSetpoint)
    }
  },
  supported_capabilities = {
    capabilities.thermostatMode,
    capabilities.thermostatHeatingSetpoint,
    capabilities.thermostatCoolingSetpoint,
    capabilities.thermostatFanMode,
    capabilities.thermostatOperatingState,
    capabilities.battery,
  },
}

local matter_driver = MatterDriver("matter-thermostat", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
