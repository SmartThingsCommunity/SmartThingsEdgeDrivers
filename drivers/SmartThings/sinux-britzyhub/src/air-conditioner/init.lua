-- SinuxSoft (c) 2025
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
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"
local utils = require "st.utils"
local log = require "log"

local version = require "version"

local SAVED_SYSTEM_MODE_IB = "__saved_system_mode_ib"
local DISALLOWED_THERMOSTAT_MODES = "__DISALLOWED_CONTROL_OPERATIONS"
local OPTIONAL_THERMOSTAT_MODES_SEEN = "__OPTIONAL_THERMOSTAT_MODES_SEEN"

local THERMOSTAT_MODE_MAP = {
  [clusters.Thermostat.types.ThermostatSystemMode.OFF]               = capabilities.thermostatMode.thermostatMode.off,
  [clusters.Thermostat.types.ThermostatSystemMode.AUTO]              = capabilities.thermostatMode.thermostatMode.auto,
  [clusters.Thermostat.types.ThermostatSystemMode.COOL]              = capabilities.thermostatMode.thermostatMode.cool,
  [clusters.Thermostat.types.ThermostatSystemMode.HEAT]              = capabilities.thermostatMode.thermostatMode.heat,
  [clusters.Thermostat.types.ThermostatSystemMode.EMERGENCY_HEATING] = capabilities.thermostatMode.thermostatMode.emergency_heat,
  [clusters.Thermostat.types.ThermostatSystemMode.PRECOOLING]        = capabilities.thermostatMode.thermostatMode.precooling,
  [clusters.Thermostat.types.ThermostatSystemMode.FAN_ONLY]          = capabilities.thermostatMode.thermostatMode.fanonly,
  [clusters.Thermostat.types.ThermostatSystemMode.DRY]               = capabilities.thermostatMode.thermostatMode.dryair,
  [clusters.Thermostat.types.ThermostatSystemMode.SLEEP]             = capabilities.thermostatMode.thermostatMode.asleep,
}

local RAC_DEVICE_TYPE_ID = 0x0072 -- Room Air Conditioner
local FAN_DEVICE_TYPE_ID = 0x002B

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"

local THERMOSTAT_MAX_TEMP_IN_C = 40.0
local THERMOSTAT_MIN_TEMP_IN_C = 5.0

local setpoint_limit_device_field = {
  MIN_SETPOINT_DEADBAND_CHECKED = "MIN_SETPOINT_DEADBAND_CHECKED",
  MIN_HEAT = "MIN_HEAT",
  MAX_HEAT = "MAX_HEAT",
  MIN_COOL = "MIN_COOL",
  MAX_COOL = "MAX_COOL",
  MIN_DEADBAND = "MIN_DEADBAND",
  MIN_TEMP = "MIN_TEMP",
  MAX_TEMP = "MAX_TEMP"
}

local profiling_data = {
  THERMOSTAT_RUNNING_STATE_SUPPORT = "__THERMOSTAT_RUNNING_STATE_SUPPORT"
}

local subscribed_attributes = {
  [capabilities.switch.ID] = {
    clusters.OnOff.attributes.OnOff
  },
  [capabilities.temperatureMeasurement.ID] = {
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
  },
  [capabilities.thermostatMode.ID] = {
    clusters.Thermostat.attributes.SystemMode,
  },
  [capabilities.thermostatCoolingSetpoint.ID] = {
    clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
  },
  [capabilities.airConditionerFanMode.ID] = {
    clusters.FanControl.attributes.FanMode
  },
}

local function tbl_contains(array, value)
  for idx, element in ipairs(array) do
    if element == value then
      return true, idx
    end
  end
  return false, nil
end

local function get_device_type(driver, device)
  for _, ep in ipairs(device.endpoints) do
    if ep.device_types ~= nil then
      for _, dt in ipairs(ep.device_types) do
        if dt.device_type_id == RAC_DEVICE_TYPE_ID then
          return RAC_DEVICE_TYPE_ID
        elseif dt.device_type_id == FAN_DEVICE_TYPE_ID then
          return FAN_DEVICE_TYPE_ID
        end
      end
    end
  end
  return false
end

local function create_fan_profile(device)
  local fan_eps = device:get_endpoints(clusters.FanControl.ID)
  local wind_eps = device:get_endpoints(clusters.FanControl.ID, {feature_bitmap = clusters.FanControl.types.FanControlFeature.WIND})
  local rock_eps = device:get_endpoints(clusters.FanControl.ID, {feature_bitmap = clusters.FanControl.types.Feature.ROCKING})
  local profile_name = ""
  if #fan_eps > 0 then
    profile_name = profile_name .. "-fan"
  end
  if #rock_eps > 0 then
    profile_name = profile_name .. "-rock"
  end
  if #wind_eps > 0 then
    profile_name = profile_name .. "-wind"
  end
  return profile_name
end

local function create_thermostat_modes_profile(device)
  local heat_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.HEATING})
  local cool_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.COOLING})

  local thermostat_modes = ""
  if #heat_eps == 0 and #cool_eps == 0 then
    return "No Heating nor Cooling Support"
  elseif #heat_eps > 0 and #cool_eps == 0 then
    thermostat_modes = thermostat_modes .. "-heating-only"
  elseif #cool_eps > 0 and #heat_eps == 0 then
    thermostat_modes = thermostat_modes .. "-cooling-only"
  end
  return thermostat_modes
end

local function profiling_data_still_required(device)
    for _, field in pairs(profiling_data) do
        if device:get_field(field) == nil then
            return true
        end
    end
    return false
end

local function match_profile(driver, device)
  if profiling_data_still_required(device) then return end

  local running_state_supported = device:get_field(profiling_data.THERMOSTAT_RUNNING_STATE_SUPPORT)

  local thermostat_eps = device:get_endpoints(clusters.Thermostat.ID)
  local humidity_eps = device:get_endpoints(clusters.RelativeHumidityMeasurement.ID)
  local device_type = get_device_type(driver, device)
  local profile_name
  if device_type == RAC_DEVICE_TYPE_ID then
    profile_name = "room-air-conditioner"

    if #humidity_eps > 0 then
      profile_name = profile_name .. "-humidity"
    end

    local fan_name = create_fan_profile(device)
    fan_name = string.gsub(fan_name, "-rock", "")
    profile_name = profile_name .. fan_name

    local thermostat_modes = create_thermostat_modes_profile(device)
    if thermostat_modes == "" then
      profile_name = profile_name .. "-heating-cooling"
    else
      device.log.warn_with({hub_logs=true}, "Device does not support both heating and cooling. No matching profile")
      return
    end

    if profile_name == "room-air-conditioner-humidity-fan-wind-heating-cooling" then
      profile_name = "room-air-conditioner"
    end

    if not running_state_supported and profile_name == "room-air-conditioner-fan-heating-cooling" then
      profile_name = profile_name .. "-nostate"
    end

  elseif device_type == FAN_DEVICE_TYPE_ID then
    profile_name = create_fan_profile(device)
    profile_name = string.sub(profile_name, 2)
    if profile_name == "fan" then
      profile_name = "fan-generic"
    end

  elseif #thermostat_eps > 0 then
    profile_name = "thermostat"

    if #humidity_eps > 0 then
      profile_name = profile_name .. "-humidity"
    end

    local fan_name = create_fan_profile(device)
    if fan_name ~= "" then
      profile_name = profile_name .. "-fan"
    end

    local thermostat_modes = create_thermostat_modes_profile(device)
    if thermostat_modes == "No Heating nor Cooling Support" then
      device.log.warn_with({hub_logs=true}, "Device does not support either heating or cooling. No matching profile")
      return
    else
      profile_name = profile_name .. thermostat_modes
    end

    if not running_state_supported then
      profile_name = profile_name .. "-nostate"
    end

  else
    device.log.warn_with({hub_logs=true}, "Device type is not supported in thermostat driver")
    return
  end

  if profile_name then
    device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({profile = profile_name})
  end
  for _, field in pairs(profiling_data) do
    device:set_field(field, nil)
  end
end

local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  end
end

local function system_mode_handler(driver, device, ib, response)
  if device:get_field(OPTIONAL_THERMOSTAT_MODES_SEEN) == nil then
    device.log.info_with({hub_logs = true}, "In the SystemMode handler: ControlSequenceOfOperation has not run yet. Exiting early.")
    device:set_field(SAVED_SYSTEM_MODE_IB, ib)
    return
  end

  local supported_modes = device:get_latest_state(device:endpoint_to_component(ib.endpoint_id), capabilities.thermostatMode.ID, capabilities.thermostatMode.supportedThermostatModes.NAME) or {}
  if tbl_contains(supported_modes, THERMOSTAT_MODE_MAP[ib.data.value].NAME) then
    device:emit_event_for_endpoint(ib.endpoint_id, THERMOSTAT_MODE_MAP[ib.data.value]())
    return
  end
  local disallowed_thermostat_modes = device:get_field(DISALLOWED_THERMOSTAT_MODES) or {}
  if tbl_contains(disallowed_thermostat_modes, THERMOSTAT_MODE_MAP[ib.data.value].NAME) then
    return
  end
  local optional_modes_seen = utils.deep_copy(device:get_field(OPTIONAL_THERMOSTAT_MODES_SEEN)) or {}
  table.insert(optional_modes_seen, THERMOSTAT_MODE_MAP[ib.data.value].NAME)
  device:set_field(OPTIONAL_THERMOSTAT_MODES_SEEN, optional_modes_seen, { persist = true })
  local sm_copy = utils.deep_copy(supported_modes)
  table.insert(sm_copy, THERMOSTAT_MODE_MAP[ib.data.value].NAME)
  local supported_modes_event = capabilities.thermostatMode.supportedThermostatModes(sm_copy, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, supported_modes_event)
  device:emit_event_for_endpoint(ib.endpoint_id, THERMOSTAT_MODE_MAP[ib.data.value]())
end

local function temp_event_handler(attribute)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local unit = "C"

    if version.rpc >= 5 then
      local event
      if attribute == capabilities.thermostatCoolingSetpoint.coolingSetpoint then
        local range = {
          minimum = device:get_field(setpoint_limit_device_field.MIN_COOL) or THERMOSTAT_MIN_TEMP_IN_C,
          maximum = device:get_field(setpoint_limit_device_field.MAX_COOL) or THERMOSTAT_MAX_TEMP_IN_C,
          step = 0.1
        }
        event = capabilities.thermostatCoolingSetpoint.coolingSetpointRange({value = range, unit = unit})
        device:emit_event_for_endpoint(ib.endpoint_id, event)
      elseif attribute == capabilities.thermostatHeatingSetpoint.heatingSetpoint then
        local MAX_TEMP_IN_C = THERMOSTAT_MAX_TEMP_IN_C
        local MIN_TEMP_IN_C = THERMOSTAT_MIN_TEMP_IN_C

        local range = {
          minimum = device:get_field(setpoint_limit_device_field.MIN_HEAT) or MIN_TEMP_IN_C,
          maximum = device:get_field(setpoint_limit_device_field.MAX_HEAT) or MAX_TEMP_IN_C,
          step = 0.1
        }
        event = capabilities.thermostatHeatingSetpoint.heatingSetpointRange({value = range, unit = unit})
        device:emit_event_for_endpoint(ib.endpoint_id, event)
      end
    end

    local temp = ib.data.value / 100.0
    device:emit_event_for_endpoint(ib.endpoint_id, attribute({value = temp, unit = unit}))
  end
end

local function fan_mode_handler(driver, device, ib, response)
  if device:supports_capability_by_id(capabilities.airConditionerFanMode.ID) then
    -- Room Air Conditioner
    if ib.data.value == clusters.FanControl.attributes.FanMode.OFF then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airConditionerFanMode.fanMode("off"))
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.LOW then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airConditionerFanMode.fanMode("low"))
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.MEDIUM then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airConditionerFanMode.fanMode("medium"))
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.HIGH then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airConditionerFanMode.fanMode("high"))
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airConditionerFanMode.fanMode("auto"))
    end
  elseif device:supports_capability_by_id(capabilities.airPurifierFanMode.ID) then
    if ib.data.value == clusters.FanControl.attributes.FanMode.OFF then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.off())
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.LOW then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.low())
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.MEDIUM then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.medium())
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.HIGH then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.high())
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.auto())
    end
  else
    -- Thermostat
    if ib.data.value == clusters.FanControl.attributes.FanMode.AUTO or
      ib.data.value == clusters.FanControl.attributes.FanMode.SMART then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatFanMode.thermostatFanMode.auto())
    elseif ib.data.value ~= clusters.FanControl.attributes.FanMode.OFF then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatFanMode.thermostatFanMode.on())
    end
  end
end

local function find_default_endpoint(device, cluster)
  local res = device.MATTER_DEFAULT_ENDPOINT
  local eps = device:get_endpoints(cluster)
  table.sort(eps)
  for _, v in ipairs(eps) do
    if v ~= 0 then
      return v
    end
  end
  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return res
end

local function component_to_endpoint(device, component_name, cluster_id)
  local component_to_endpoint_map = device:get_field(COMPONENT_TO_ENDPOINT_MAP)
  if component_to_endpoint_map ~= nil and component_to_endpoint_map[component_name] ~= nil then
    return component_to_endpoint_map[component_name]
  end
  if not cluster_id then return device.MATTER_DEFAULT_ENDPOINT end
  return find_default_endpoint(device, cluster_id)
end

local function handle_switch_on(driver, device, cmd)
  local endpoint_id = component_to_endpoint(device, cmd.component, clusters.OnOff.ID)
  local req = clusters.OnOff.server.commands.On(device, endpoint_id)
  device:send(req)
end

local function handle_switch_off(driver, device, cmd)
  local endpoint_id = component_to_endpoint(device, cmd.component, clusters.OnOff.ID)
  local req = clusters.OnOff.server.commands.Off(device, endpoint_id)
  device:send(req)
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
    device:send(clusters.Thermostat.attributes.SystemMode:write(device, component_to_endpoint(device, cmd.component, clusters.Thermostat.ID), mode_id))
  end
end

local function set_fan_mode(driver, device, cmd)
  local fan_mode_id
  if cmd.args.fanMode == "off" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.OFF
  elseif cmd.args.fanMode == "low" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.fanMode == "medium" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.MEDIUM
  elseif cmd.args.fanMode == "high" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.HIGH
  elseif cmd.args.fanMode == "auto" then
    fan_mode_id = clusters.FanControl.attributes.FanMode.AUTO
  else
    fan_mode_id = clusters.FanControl.attributes.FanMode.OFF
  end
  if fan_mode_id then
    device:send(clusters.FanControl.attributes.FanMode:write(device, component_to_endpoint(device, cmd.component, clusters.FanControl.ID), fan_mode_id))
  end
end

local function set_setpoint(setpoint)
  return function(driver, device, cmd)
    local endpoint_id = component_to_endpoint(device, cmd.component, clusters.Thermostat.ID)
    local MAX_TEMP_IN_C = THERMOSTAT_MAX_TEMP_IN_C
    local MIN_TEMP_IN_C = THERMOSTAT_MIN_TEMP_IN_C
    local value = cmd.args.setpoint
    if (value > MAX_TEMP_IN_C) then
      value = utils.f_to_c(value)
    end

    local cached_cooling_val, cooling_setpoint = device:get_latest_state(
      cmd.component, capabilities.thermostatCoolingSetpoint.ID,
      capabilities.thermostatCoolingSetpoint.coolingSetpoint.NAME,
      MAX_TEMP_IN_C, { value = MAX_TEMP_IN_C, unit = "C" }
    )
    if cooling_setpoint and cooling_setpoint.unit == "F" then
      cached_cooling_val = utils.f_to_c(cached_cooling_val)
    end
    local cached_heating_val, heating_setpoint = device:get_latest_state(
      cmd.component, capabilities.thermostatHeatingSetpoint.ID,
      capabilities.thermostatHeatingSetpoint.heatingSetpoint.NAME,
      MIN_TEMP_IN_C, { value = MIN_TEMP_IN_C, unit = "C" }
    )
    if heating_setpoint and heating_setpoint.unit == "F" then
      cached_heating_val = utils.f_to_c(cached_heating_val)
    end
    local is_auto_capable = #device:get_endpoints(
      clusters.Thermostat.ID,
      {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.AUTOMODE}
    ) > 0

    local setpoint_type = string.match(setpoint.NAME, "Heat") or "Cool"
    local deadband = device:get_field(setpoint_limit_device_field.MIN_DEADBAND) or 2.5
    if setpoint_type == "Heat" then
      local min = device:get_field(setpoint_limit_device_field.MIN_HEAT) or MIN_TEMP_IN_C
      local max = device:get_field(setpoint_limit_device_field.MAX_HEAT) or MAX_TEMP_IN_C
      if value < min or value > max then
        log.warn(string.format("Invalid setpoint (%s) outside the min (%s) and the max (%s)", value, min, max))
        device:emit_event_for_endpoint(endpoint_id, capabilities.thermostatHeatingSetpoint.heatingSetpoint(heating_setpoint, {state_change = true}))
        return
      end
      if is_auto_capable and value > (cached_cooling_val - deadband) then
        log.warn(string.format("Invalid setpoint (%s) is greater than the cooling setpoint (%s) with the deadband (%s)", value, cooling_setpoint, deadband))
        device:emit_event_for_endpoint(endpoint_id, capabilities.thermostatHeatingSetpoint.heatingSetpoint(heating_setpoint, {state_change = true}))
        return
      end
    else
      local min = device:get_field(setpoint_limit_device_field.MIN_COOL) or MIN_TEMP_IN_C
      local max = device:get_field(setpoint_limit_device_field.MAX_COOL) or MAX_TEMP_IN_C
      if value < min or value > max then
        log.warn(string.format("Invalid setpoint (%s) outside the min (%s) and the max (%s)", value, min, max))
        device:emit_event_for_endpoint(endpoint_id, capabilities.thermostatCoolingSetpoint.coolingSetpoint(cooling_setpoint, {state_change = true}))
        return
      end
      if is_auto_capable and value < (cached_heating_val + deadband) then
        log.warn(string.format("Invalid setpoint (%s) is less than the heating setpoint (%s) with the deadband (%s)", value, heating_setpoint, deadband))
        device:emit_event_for_endpoint(endpoint_id, capabilities.thermostatCoolingSetpoint.coolingSetpoint(cooling_setpoint, {state_change = true}))
        return
      end
    end
    device:send(setpoint:write(device, component_to_endpoint(device, cmd.component, clusters.Thermostat.ID), utils.round(value * 100.0)))
  end
end

local function device_init(driver, device)
  device:subscribe()
  device:set_component_to_endpoint_fn(component_to_endpoint)
  if not device:get_field(setpoint_limit_device_field.MIN_SETPOINT_DEADBAND_CHECKED) then
    local auto_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.AUTOMODE})
    if #auto_eps ~= 0 and device:get_field(setpoint_limit_device_field.MIN_DEADBAND) == nil then
      local deadband_read = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
      deadband_read:merge(clusters.Thermostat.attributes.MinSetpointDeadBand:read())
      device:send(deadband_read)
    end
  end
end

local function do_configure(driver, device)
  match_profile(driver, device)
end

local function info_changed(driver, device, event, args)
  for cap_id, attributes in pairs(subscribed_attributes) do
    if device:supports_capability_by_id(cap_id) then
      for _, attr in ipairs(attributes) do
        device:add_subscribed_attribute(attr)
      end
    end
  end
  device:subscribe()
end

local function can_handle(opts, driver, device)
  return device.label:find("에어컨") ~= nil
end

local air_conditioner_handler = {
  NAME = "Air Conditioner Handler",
  can_handle = can_handle,
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
    infoChanged = info_changed,
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.Thermostat.ID] = {
        [clusters.Thermostat.attributes.SystemMode.ID] = system_mode_handler,
        [clusters.Thermostat.attributes.OccupiedCoolingSetpoint.ID] = temp_event_handler(capabilities.thermostatCoolingSetpoint.coolingSetpoint),
      },
      [clusters.FanControl.ID] = {
        [clusters.FanControl.attributes.FanMode.ID] = fan_mode_handler,
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler(capabilities.temperatureMeasurement.temperature),
      }
    }
  },
  subscribed_attributes = subscribed_attributes,
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = set_thermostat_mode,
    },
    [capabilities.airConditionerFanMode.ID] = {
      [capabilities.airConditionerFanMode.commands.setFanMode.NAME] = set_fan_mode,
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = set_setpoint(clusters.Thermostat.attributes.OccupiedCoolingSetpoint),
    },
  },
  supported_capabilities = {
    capabilities.switch,
    capabilities.thermostatMode,
    capabilities.airConditionerFanMode,
    capabilities.thermostatCoolingSetpoint,
    capabilities.temperatureMeasurement,
  }
}

return air_conditioner_handler
