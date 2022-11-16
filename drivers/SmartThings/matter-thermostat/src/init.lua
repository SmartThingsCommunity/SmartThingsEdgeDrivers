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

local function device_init(driver, device)
  device:subscribe()
end

local function do_configure(driver, device)
  local heat_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.HEATING})
  local cool_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.COOLING})
  local thermo_eps = device:get_endpoints(clusters.Thermostat.ID)
  local fan_eps = device:get_endpoints(clusters.FanControl.ID)
  local humidity_eps = device:get_endpoints(clusters.RelativeHumidityMeasurement.ID)
  local running_state_eps = device:get_endpoints(
    clusters.Thermostat.ID,
    {attribute_id = clusters.Thermostat.attributes.ThermostatRunningState.ID}
  )
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

    if #running_state_eps == 0 then
      profile_name = profile_name .. "-nostate"
    end

    log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({profile = profile_name})
  else
    log.warn_with({hub_logs=true}, "Device does not support thermostat cluster")
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

local function f_to_c(f)
  local res = (f - 32) * (5 / 9.0)
  return res
end

local function set_setpoint(setpoint)
  return function(driver, device, cmd)
    local value = cmd.args.setpoint
    if (value >= 40) then -- assume this is a fahrenheit value
      value = f_to_c(value)
    end

    device:send(setpoint:write(device, device:component_to_endpoint(cmd.component), utils.round(value * 100.0)))
  end
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
}

local matter_driver = MatterDriver("matter-thermostat", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
