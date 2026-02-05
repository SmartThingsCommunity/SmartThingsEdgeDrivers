-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local log = require "log"
local version = require "version"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local st_utils = require "st.utils"
local fields = require "thermostat_utils.fields"
local thermostat_utils = require "thermostat_utils.utils"

if version.api < 10 then
  clusters.HepaFilterMonitoring = require "embedded_clusters.HepaFilterMonitoring"
  clusters.ActivatedCarbonFilterMonitoring = require "embedded_clusters.ActivatedCarbonFilterMonitoring"
end

if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded_clusters.ElectricalEnergyMeasurement"
end

if version.api < 13 then
  clusters.WaterHeaterMode = require "embedded_clusters.WaterHeaterMode"
end

local AttributeHandlers = {}


-- [[ THERMOSTAT CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.thermostat_attribute_list_handler(driver, device, ib, response)
  local device_cfg = require "thermostat_utils.device_configuration"
  for _, attr in ipairs(ib.data.elements) do
    -- mark whether the optional attribute ThermostatRunningState (0x029) is present and try profiling
    if attr.value == 0x029 then
      device:set_field(fields.profiling_data.THERMOSTAT_RUNNING_STATE_SUPPORT, true)
      device_cfg.match_profile(device)
      return
    end
  end
  device:set_field(fields.profiling_data.THERMOSTAT_RUNNING_STATE_SUPPORT, false)
  device_cfg.match_profile(device)
end

function AttributeHandlers.system_mode_handler(driver, device, ib, response)
  if device:get_field(fields.OPTIONAL_THERMOSTAT_MODES_SEEN) == nil then -- this being nil means the control_sequence_of_operation_handler hasn't run.
    device.log.info_with({hub_logs = true}, "In the SystemMode handler: ControlSequenceOfOperation has not run yet. Exiting early.")
    device:set_field(fields.SAVED_SYSTEM_MODE_IB, ib)
    return
  end

  local supported_modes = device:get_latest_state(device:endpoint_to_component(ib.endpoint_id), capabilities.thermostatMode.ID, capabilities.thermostatMode.supportedThermostatModes.NAME) or {}
  -- check that the given mode was in the supported modes list
  if thermostat_utils.tbl_contains(supported_modes, fields.THERMOSTAT_MODE_MAP[ib.data.value].NAME) then
    device:emit_event_for_endpoint(ib.endpoint_id, fields.THERMOSTAT_MODE_MAP[ib.data.value]())
    return
  end
  -- if the value is not found in the supported modes list, check if it's disallowed and early return if so.
  local disallowed_thermostat_modes = device:get_field(fields.DISALLOWED_THERMOSTAT_MODES) or {}
  if thermostat_utils.tbl_contains(disallowed_thermostat_modes, fields.THERMOSTAT_MODE_MAP[ib.data.value].NAME) then
    return
  end
  -- if we get here, then the reported mode is allowed and not in our mode map
  -- add the mode to the OPTIONAL_THERMOSTAT_MODES_SEEN and supportedThermostatModes tables
  local optional_modes_seen = st_utils.deep_copy(device:get_field(fields.OPTIONAL_THERMOSTAT_MODES_SEEN)) or {}
  table.insert(optional_modes_seen, fields.THERMOSTAT_MODE_MAP[ib.data.value].NAME)
  device:set_field(fields.OPTIONAL_THERMOSTAT_MODES_SEEN, optional_modes_seen, {persist=true})
  local sm_copy = st_utils.deep_copy(supported_modes)
  table.insert(sm_copy, fields.THERMOSTAT_MODE_MAP[ib.data.value].NAME)
  local supported_modes_event = capabilities.thermostatMode.supportedThermostatModes(sm_copy, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, supported_modes_event)
  device:emit_event_for_endpoint(ib.endpoint_id, fields.THERMOSTAT_MODE_MAP[ib.data.value]())
end

function AttributeHandlers.thermostat_running_state_handler(driver, device, ib, response)
  for mode, operating_state in pairs(fields.THERMOSTAT_OPERATING_MODE_MAP) do
    if ((ib.data.value >> mode) & 1) > 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, operating_state())
      return
    end
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatOperatingState.thermostatOperatingState.idle())
end

function AttributeHandlers.control_sequence_of_operation_handler(driver, device, ib, response)
  -- The ControlSequenceOfOperation attribute only directly specifies what can't be operated by the operating environment, not what can.
  -- However, we assert here that a Cooling enum value implies that SystemMode supports cooling, and the same for a Heating enum.
  -- We also assert that Off is supported if the switch capability is not supported, though per spec this is optional.
  if device:get_field(fields.OPTIONAL_THERMOSTAT_MODES_SEEN) == nil and device:supports_capability(capabilities.switch) == false then
    device:set_field(fields.OPTIONAL_THERMOSTAT_MODES_SEEN, {capabilities.thermostatMode.thermostatMode.off.NAME}, {persist=true})
  end
  local supported_modes = st_utils.deep_copy(device:get_field(fields.OPTIONAL_THERMOSTAT_MODES_SEEN))
  local disallowed_mode_operations = {}

  local modes_for_inclusion = {}
  if ib.data.value <= clusters.Thermostat.attributes.ControlSequenceOfOperation.COOLING_WITH_REHEAT then
    local _, found_idx = thermostat_utils.tbl_contains(supported_modes, capabilities.thermostatMode.thermostatMode.emergency_heat.NAME)
    if found_idx then
      table.remove(supported_modes, found_idx) -- if seen before, remove now
    end
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.cool.NAME)
    table.insert(disallowed_mode_operations, capabilities.thermostatMode.thermostatMode.heat.NAME)
    table.insert(disallowed_mode_operations, capabilities.thermostatMode.thermostatMode.emergency_heat.NAME)
  elseif ib.data.value <= clusters.Thermostat.attributes.ControlSequenceOfOperation.HEATING_WITH_REHEAT then
    local _, found_idx = thermostat_utils.tbl_contains(supported_modes, capabilities.thermostatMode.thermostatMode.precooling.NAME)
    if found_idx then
      table.remove(supported_modes, found_idx) -- if seen before, remove now
    end
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.heat.NAME)
    table.insert(disallowed_mode_operations, capabilities.thermostatMode.thermostatMode.cool.NAME)
    table.insert(disallowed_mode_operations, capabilities.thermostatMode.thermostatMode.precooling.NAME)
  elseif ib.data.value <= clusters.Thermostat.attributes.ControlSequenceOfOperation.COOLING_AND_HEATING_WITH_REHEAT then
    table.insert(modes_for_inclusion, capabilities.thermostatMode.thermostatMode.cool.NAME)
    table.insert(modes_for_inclusion, capabilities.thermostatMode.thermostatMode.heat.NAME)
  end

  -- check whether the Auto Mode should be supported in SystemMode, though this is unrelated to ControlSequenceOfOperation
  local auto = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.AUTOMODE})
  if #auto > 0 then
    table.insert(modes_for_inclusion, capabilities.thermostatMode.thermostatMode.auto.NAME)
  else
    table.insert(disallowed_mode_operations, capabilities.thermostatMode.thermostatMode.auto.NAME)
  end

  -- if a disallowed value was once allowed and added, it should be removed now.
  for index, mode in pairs(supported_modes) do
    if thermostat_utils.tbl_contains(disallowed_mode_operations, mode) then
      table.remove(supported_modes, index)
    end
  end
  -- do not include any values twice
  for _, mode in pairs(modes_for_inclusion) do
    if not thermostat_utils.tbl_contains(supported_modes, mode) then
      table.insert(supported_modes, mode)
    end
  end
  device:set_field(fields.DISALLOWED_THERMOSTAT_MODES, disallowed_mode_operations)
  local event = capabilities.thermostatMode.supportedThermostatModes(supported_modes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)

  -- will be set by the SystemMode handler if this handler hasn't run yet.
  if device:get_field(fields.SAVED_SYSTEM_MODE_IB) then
    AttributeHandlers.system_mode_handler(driver, device, device:get_field(fields.SAVED_SYSTEM_MODE_IB), response)
    device:set_field(fields.SAVED_SYSTEM_MODE_IB, nil)
  end
end

function AttributeHandlers.min_setpoint_deadband_handler(driver, device, ib, response)
  local val = ib.data.value / 10.0
  log.info("Setting " .. fields.setpoint_limit_device_field.MIN_DEADBAND .. " to " .. string.format("%s", val))
  device:set_field(fields.setpoint_limit_device_field.MIN_DEADBAND, val, { persist = true })
  device:set_field(fields.setpoint_limit_device_field.MIN_SETPOINT_DEADBAND_CHECKED, true, {persist = true})
end

function AttributeHandlers.abs_heat_setpoint_limit_factory(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local MAX_TEMP_IN_C = fields.THERMOSTAT_MAX_TEMP_IN_C
    local MIN_TEMP_IN_C = fields.THERMOSTAT_MIN_TEMP_IN_C
    local is_water_heater_device = (thermostat_utils.get_device_type(device) == fields.WATER_HEATER_DEVICE_TYPE_ID)
    if is_water_heater_device then
      MAX_TEMP_IN_C = fields.WATER_HEATER_MAX_TEMP_IN_C
      MIN_TEMP_IN_C = fields.WATER_HEATER_MIN_TEMP_IN_C
    end
    local val = ib.data.value / 100.0
    val = st_utils.clamp_value(val, MIN_TEMP_IN_C, MAX_TEMP_IN_C)
    device:set_field(minOrMax, val)
    local min = device:get_field(fields.setpoint_limit_device_field.MIN_HEAT)
    local max = device:get_field(fields.setpoint_limit_device_field.MAX_HEAT)
    if min ~= nil and max ~= nil then
      if min < max then
        -- Only emit the capability for RPC version >= 5 (unit conversion for
        -- heating setpoint range capability is only supported for RPC >= 5)
        if version.rpc >= 5 then
          device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatHeatingSetpoint.heatingSetpointRange({ value = { minimum = min, maximum = max, step = 0.1 }, unit = "C" }))
        end
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min heating setpoint %d that is not lower than the reported max %d", min, max))
      end
    end
  end
end

function AttributeHandlers.abs_cool_setpoint_limit_factory(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local val = ib.data.value / 100.0
    val = st_utils.clamp_value(val, fields.THERMOSTAT_MIN_TEMP_IN_C, fields.THERMOSTAT_MAX_TEMP_IN_C)
    device:set_field(minOrMax, val)
    local min = device:get_field(fields.setpoint_limit_device_field.MIN_COOL)
    local max = device:get_field(fields.setpoint_limit_device_field.MAX_COOL)
    if min ~= nil and max ~= nil then
      if min < max then
        -- Only emit the capability for RPC version >= 5 (unit conversion for
        -- cooling setpoint range capability is only supported for RPC >= 5)
        if version.rpc >= 5 then
          device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatCoolingSetpoint.coolingSetpointRange({ value = { minimum = min, maximum = max, step = 0.1 }, unit = "C" }))
        end
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min cooling setpoint %d that is not lower than the reported max %d", min, max))
      end
    end
  end
end


-- [[ TEMPERATURE MEASUREMENT CLUSER ATTRIBUTES ]] --

function AttributeHandlers.temperature_handler_factory(attribute)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local unit = "C"

    -- Only emit the capability for RPC version >= 5, since unit conversion for
    -- range capabilities is only supported in that case.
    if version.rpc >= 5 then
      local event
      if attribute == capabilities.thermostatCoolingSetpoint.coolingSetpoint then
        local range = {
          minimum = device:get_field(fields.setpoint_limit_device_field.MIN_COOL) or fields.THERMOSTAT_MIN_TEMP_IN_C,
          maximum = device:get_field(fields.setpoint_limit_device_field.MAX_COOL) or fields.THERMOSTAT_MAX_TEMP_IN_C,
          step = 0.1
        }
        event = capabilities.thermostatCoolingSetpoint.coolingSetpointRange({value = range, unit = unit})
        device:emit_event_for_endpoint(ib.endpoint_id, event)
      elseif attribute == capabilities.thermostatHeatingSetpoint.heatingSetpoint then
        local MAX_TEMP_IN_C = fields.THERMOSTAT_MAX_TEMP_IN_C
        local MIN_TEMP_IN_C = fields.THERMOSTAT_MIN_TEMP_IN_C
        local is_water_heater_device = thermostat_utils.get_device_type(device) == fields.WATER_HEATER_DEVICE_TYPE_ID
        if is_water_heater_device then
          MAX_TEMP_IN_C = fields.WATER_HEATER_MAX_TEMP_IN_C
          MIN_TEMP_IN_C = fields.WATER_HEATER_MIN_TEMP_IN_C
        end

        local range = {
          minimum = device:get_field(fields.setpoint_limit_device_field.MIN_HEAT) or MIN_TEMP_IN_C,
          maximum = device:get_field(fields.setpoint_limit_device_field.MAX_HEAT) or MAX_TEMP_IN_C,
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

function AttributeHandlers.temperature_measured_value_bounds_factory(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local temp = ib.data.value / 100.0
    local unit = "C"
    temp = st_utils.clamp_value(temp, fields.THERMOSTAT_MIN_TEMP_IN_C, fields.THERMOSTAT_MAX_TEMP_IN_C)
    thermostat_utils.set_field_for_endpoint(device, minOrMax, ib.endpoint_id, temp)
    local min = thermostat_utils.get_field_for_endpoint(device, fields.setpoint_limit_device_field.MIN_TEMP, ib.endpoint_id)
    local max = thermostat_utils.get_field_for_endpoint(device, fields.setpoint_limit_device_field.MAX_TEMP, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        -- Only emit the capability for RPC version >= 5 (unit conversion for
        -- temperature range capability is only supported for RPC >= 5)
        if version.rpc >= 5 then
          device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = min, maximum = max }, unit = unit }))
        end
        thermostat_utils.set_field_for_endpoint(device, fields.setpoint_limit_device_field.MIN_TEMP, ib.endpoint_id, nil)
        thermostat_utils.set_field_for_endpoint(device, fields.setpoint_limit_device_field.MAX_TEMP, ib.endpoint_id, nil)
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min temperature %d that is not lower than the reported max temperature %d", min, max))
      end
    end
  end
end


--[[ FAN CONTROL CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.fan_mode_handler(driver, device, ib, response)
  local fan_mode_event = {
    [clusters.FanControl.attributes.FanMode.OFF]    = { capabilities.fanMode.fanMode.off(),
                                                        capabilities.airConditionerFanMode.fanMode("off"),
                                                        capabilities.airPurifierFanMode.airPurifierFanMode.off(),
                                                        nil }, -- 'OFF' is not supported by thermostatFanMode
    [clusters.FanControl.attributes.FanMode.LOW]    = { capabilities.fanMode.fanMode.low(),
                                                        capabilities.airConditionerFanMode.fanMode("low"),
                                                        capabilities.airPurifierFanMode.airPurifierFanMode.low(),
                                                        capabilities.thermostatFanMode.thermostatFanMode.on() },
    [clusters.FanControl.attributes.FanMode.MEDIUM] = { capabilities.fanMode.fanMode.medium(),
                                                        capabilities.airConditionerFanMode.fanMode("medium"),
                                                        capabilities.airPurifierFanMode.airPurifierFanMode.medium(),
                                                        capabilities.thermostatFanMode.thermostatFanMode.on() },
    [clusters.FanControl.attributes.FanMode.HIGH]   = { capabilities.fanMode.fanMode.high(),
                                                        capabilities.airConditionerFanMode.fanMode("high"),
                                                        capabilities.airPurifierFanMode.airPurifierFanMode.high(),
                                                        capabilities.thermostatFanMode.thermostatFanMode.on() },
    [clusters.FanControl.attributes.FanMode.ON]     = { capabilities.fanMode.fanMode.auto(),
                                                        capabilities.airConditionerFanMode.fanMode("auto"),
                                                        capabilities.airPurifierFanMode.airPurifierFanMode.auto(),
                                                        capabilities.thermostatFanMode.thermostatFanMode.on() },
    [clusters.FanControl.attributes.FanMode.AUTO]   = { capabilities.fanMode.fanMode.auto(),
                                                        capabilities.airConditionerFanMode.fanMode("auto"),
                                                        capabilities.airPurifierFanMode.airPurifierFanMode.auto(),
                                                        capabilities.thermostatFanMode.thermostatFanMode.auto() },
    [clusters.FanControl.attributes.FanMode.SMART]  = { capabilities.fanMode.fanMode.auto(),
                                                        capabilities.airConditionerFanMode.fanMode("auto"),
                                                        capabilities.airPurifierFanMode.airPurifierFanMode.auto(),
                                                        capabilities.thermostatFanMode.thermostatFanMode.auto() }
  }
  local fan_mode_idx = device:supports_capability_by_id(capabilities.fanMode.ID) and 1 or
    device:supports_capability_by_id(capabilities.airConditionerFanMode.ID) and 2 or
    device:supports_capability_by_id(capabilities.airPurifierFanMode.ID) and 3 or
    device:supports_capability_by_id(capabilities.thermostatFanMode.ID) and 4
  if fan_mode_idx ~= false and fan_mode_event[ib.data.value][fan_mode_idx] then
    device:emit_event_for_endpoint(ib.endpoint_id, fan_mode_event[ib.data.value][fan_mode_idx])
  else
    log.warn(string.format("Invalid Fan Mode (%s)", ib.data.value))
  end
end

function AttributeHandlers.fan_mode_sequence_handler(driver, device, ib, response)
  local supportedFanModes, supported_fan_modes_attribute
  if ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH then
    supportedFanModes = { "off", "low", "medium", "high" }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH then
    supportedFanModes = { "off", "low", "high" }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO then
    supportedFanModes = { "off", "low", "medium", "high", "auto" }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH_AUTO then
    supportedFanModes = { "off", "low", "high", "auto" }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_HIGH_AUTO then
    supportedFanModes = { "off", "high", "auto" }
  else
    supportedFanModes = { "off", "high" }
  end

  if device:supports_capability_by_id(capabilities.airPurifierFanMode.ID) then
    supported_fan_modes_attribute = capabilities.airPurifierFanMode.supportedAirPurifierFanModes
  elseif device:supports_capability_by_id(capabilities.airConditionerFanMode.ID) then
    supported_fan_modes_attribute = capabilities.airConditionerFanMode.supportedAcFanModes
  elseif device:supports_capability_by_id(capabilities.thermostatFanMode.ID) then
    supported_fan_modes_attribute = capabilities.thermostatFanMode.supportedThermostatFanModes
    -- Our thermostat fan mode control is not granular enough to handle all of the supported modes
    if ib.data.value >= clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO and
      ib.data.value <= clusters.FanControl.attributes.FanModeSequence.OFF_ON_AUTO then
      supportedFanModes = { "auto", "on" }
    else
      supportedFanModes = { "on" }
    end
  else
    supported_fan_modes_attribute = capabilities.fanMode.supportedFanModes
  end

  local event = supported_fan_modes_attribute(supportedFanModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

function AttributeHandlers.percent_current_handler(driver, device, ib, response)
  local speed = 0
  if ib.data.value ~= nil then
    speed = st_utils.clamp_value(ib.data.value, fields.MIN_ALLOWED_PERCENT_VALUE, fields.MAX_ALLOWED_PERCENT_VALUE)
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanSpeedPercent.percent(speed))
end

function AttributeHandlers.wind_support_handler(driver, device, ib, response)
  local supported_wind_modes = {capabilities.windMode.windMode.noWind.NAME}
  for mode, wind_mode in pairs(fields.WIND_MODE_MAP) do
    if ((ib.data.value >> mode) & 1) > 0 then
      table.insert(supported_wind_modes, wind_mode.NAME)
    end
  end
  local event = capabilities.windMode.supportedWindModes(supported_wind_modes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

function AttributeHandlers.wind_setting_handler(driver, device, ib, response)
  for index, wind_mode in pairs(fields.WIND_MODE_MAP) do
    if ((ib.data.value >> index) & 1) > 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, wind_mode())
      return
    end
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windMode.windMode.noWind())
end

function AttributeHandlers.rock_support_handler(driver, device, ib, response)
  local supported_rock_modes = {capabilities.fanOscillationMode.fanOscillationMode.off.NAME}
  for mode, rock_mode in pairs(fields.ROCK_MODE_MAP) do
    if ((ib.data.value >> mode) & 1) > 0 then
      table.insert(supported_rock_modes, rock_mode.NAME)
    end
  end
  local event = capabilities.fanOscillationMode.supportedFanOscillationModes(supported_rock_modes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

function AttributeHandlers.rock_setting_handler(driver, device, ib, response)
  for index, rock_mode in pairs(fields.ROCK_MODE_MAP) do
    if ((ib.data.value >> index) & 1) > 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, rock_mode())
      return
    end
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanOscillationMode.fanOscillationMode.off())
end


-- [[ HEPA FILTER MONITORING CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.hepa_filter_condition_handler(driver, device, ib, response)
  local component = device.profile.components["hepaFilter"]
  local condition = ib.data.value
  device:emit_component_event(component, capabilities.filterState.filterLifeRemaining(condition))
end

function AttributeHandlers.hepa_filter_change_indication_handler(driver, device, ib, response)
  local component = device.profile.components["hepaFilter"]
  if ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.OK then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.WARNING then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.CRITICAL then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.replace())
  end
end


-- [[ ACTIVATED CARBON FILTER MONITORING CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.activated_carbon_filter_condition_handler(driver, device, ib, response)
  local component = device.profile.components["activatedCarbonFilter"]
  local condition = ib.data.value
  device:emit_component_event(component, capabilities.filterState.filterLifeRemaining(condition))
end

function AttributeHandlers.activated_carbon_filter_change_indication_handler(driver, device, ib, response)
  local component = device.profile.components["activatedCarbonFilter"]
  if ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.OK then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.WARNING then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.CRITICAL then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.replace())
  end
end


--[[ AIR QUALITY SENSOR CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.air_quality_handler(driver, device, ib, response)
  local state = ib.data.value
  if state == 0 then -- Unknown
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.unknown())
  elseif state == 1 then -- Good
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.good())
  elseif state == 2 then -- Fair
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.moderate())
  elseif state == 3 then -- Moderate
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.slightlyUnhealthy())
  elseif state == 4 then -- Poor
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.unhealthy())
  elseif state == 5 then -- VeryPoor
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.veryUnhealthy())
  elseif state == 6 then -- ExtremelyPoor
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airQualityHealthConcern.airQualityHealthConcern.hazardous())
  end
end


-- [[ <GENERIC> CONCENTRATION CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.concentration_measurement_unit_factory(capability_name)
  return function(driver, device, ib, response)
    device:set_field(capability_name.."_unit", ib.data.value, {persist = true})
  end
end

function AttributeHandlers.concentration_level_value_factory(attribute)
  return function(driver, device, ib, response)
    device:emit_event_for_endpoint(ib.endpoint_id, attribute(fields.level_strings[ib.data.value]))
  end
end

function AttributeHandlers.concentration_measured_value_factory(capability_name, attribute, target_unit)
  return function(driver, device, ib, response)
    local reporting_unit = device:get_field(capability_name.."_unit")

    if not reporting_unit then
      reporting_unit = fields.unit_default[capability_name]
      device:set_field(capability_name.."_unit", reporting_unit, {persist = true})
    end

    local value = nil
    if reporting_unit then
      value = thermostat_utils.unit_conversion(ib.data.value, reporting_unit, target_unit, capability_name)
    end

    if value then
      device:emit_event_for_endpoint(ib.endpoint_id, attribute({value = value, unit = fields.unit_strings[target_unit]}))
      -- handle case where device profile supports both fineDustLevel and dustLevel
      if capability_name == capabilities.fineDustSensor.NAME and device:supports_capability(capabilities.dustSensor) then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.dustSensor.fineDustLevel({value = value, unit = fields.unit_strings[target_unit]}))
      end
    end
  end
end


-- [[ POWER SOURCE CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.bat_percent_remaining_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

function AttributeHandlers.bat_charge_level_handler(driver, device, ib, response)
  if ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.OK then
    device:emit_event(capabilities.batteryLevel.battery.normal())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.WARNING then
    device:emit_event(capabilities.batteryLevel.battery.warning())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.CRITICAL then
    device:emit_event(capabilities.batteryLevel.battery.critical())
  end
end

function AttributeHandlers.power_source_attribute_list_handler(driver, device, ib, response)
  local device_cfg = require "thermostat_utils.device_configuration"
  for _, attr in ipairs(ib.data.elements) do
    -- mark if the device if BatPercentRemaining (Attribute ID 0x0C) or
    -- BatChargeLevel (Attribute ID 0x0E) is present and try profiling.
    if attr.value == 0x0C then
      device:set_field(fields.profiling_data.BATTERY_SUPPORT, fields.battery_support.BATTERY_PERCENTAGE)
      device_cfg.match_profile(device)
      return
    elseif attr.value == 0x0E then
      device:set_field(fields.profiling_data.BATTERY_SUPPORT, fields.battery_support.BATTERY_LEVEL)
      device_cfg.match_profile(device)
      return
    end
  end
end


-- [[ ELECTRICAL POWER MEASUREMENT CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.active_power_handler(driver, device, ib, response)
  if ib.data.value then
    local watt_value = ib.data.value / 1000
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.powerMeter.power({ value = watt_value, unit = "W" }))
    if type(device.register_native_capability_attr_handler) == "function" then
      device:register_native_capability_attr_handler("powerMeter","power")
    end
  end
end


-- [[ ELECTRICAL ENERGY MEASUREMENT CLUSTER ATTRIBUTES ]] --

local function periodic_energy_imported_handler(driver, device, ib, response)
  if ib.data then
    if version.api < 11 then
      clusters.ElectricalEnergyMeasurement.server.attributes.PeriodicEnergyImported:augment_type(ib.data)
    end
    local endpoint_id = string.format(ib.endpoint_id)
    local energy_imported_Wh = st_utils.round(ib.data.elements.energy.value / 1000) --convert mWh to Wh
    local cumulative_energy_imported = device:get_field(fields.TOTAL_CUMULATIVE_ENERGY_IMPORTED_MAP) or {}
    cumulative_energy_imported[endpoint_id] = cumulative_energy_imported[endpoint_id] or 0
    cumulative_energy_imported[endpoint_id] = cumulative_energy_imported[endpoint_id] + energy_imported_Wh
    device:set_field(fields.TOTAL_CUMULATIVE_ENERGY_IMPORTED_MAP, cumulative_energy_imported, { persist = true })
    local total_cumulative_energy_imported = thermostat_utils.get_total_cumulative_energy_imported(device)
    device:emit_component_event(device.profile.components["main"], ib.endpoint_id, capabilities.energyMeter.energy({value = total_cumulative_energy_imported, unit = "Wh"}))
    thermostat_utils.report_power_consumption_to_st_energy(device, total_cumulative_energy_imported)
  end
end

local function cumulative_energy_imported_handler(driver, device, ib, response)
  if ib.data then
    if version.api < 11 then
      clusters.ElectricalEnergyMeasurement.server.attributes.CumulativeEnergyImported:augment_type(ib.data)
    end
    local endpoint_id = string.format(ib.endpoint_id)
    local cumulative_energy_imported = device:get_field(fields.TOTAL_CUMULATIVE_ENERGY_IMPORTED_MAP) or {}
    local cumulative_energy_imported_Wh = st_utils.round( ib.data.elements.energy.value / 1000) -- convert mWh to Wh
    cumulative_energy_imported[endpoint_id] = cumulative_energy_imported_Wh
    device:set_field(fields.TOTAL_CUMULATIVE_ENERGY_IMPORTED_MAP, cumulative_energy_imported, { persist = true })
    local total_cumulative_energy_imported = thermostat_utils.get_total_cumulative_energy_imported(device)
    device:emit_component_event(device.profile.components["main"], capabilities.energyMeter.energy({ value = total_cumulative_energy_imported, unit = "Wh" }))
    thermostat_utils.report_power_consumption_to_st_energy(device, total_cumulative_energy_imported)
  end
end

function AttributeHandlers.energy_imported_factory(is_cumulative_report)
  return function(driver, device, ib, response)
    if is_cumulative_report then
      cumulative_energy_imported_handler(driver, device, ib, response)
    elseif device:get_field(fields.CUMULATIVE_REPORTS_NOT_SUPPORTED) then
      periodic_energy_imported_handler(driver, device, ib, response)
    end
  end
end


-- [[ WATER HEATER MODE CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.water_heater_supported_modes_handler(driver, device, ib, response)
  local supportWaterHeaterModes = {}
  local supportWaterHeaterModesWithIdx = {}
  for _, mode in ipairs(ib.data.elements) do
    if version.api < 13 then
      clusters.WaterHeaterMode.types.ModeOptionStruct:augment_type(mode)
    end
    table.insert(supportWaterHeaterModes, mode.elements.label.value)
    table.insert(supportWaterHeaterModesWithIdx, {mode.elements.mode.value, mode.elements.label.value})
  end
  device:set_field(fields.SUPPORTED_WATER_HEATER_MODES_WITH_IDX, supportWaterHeaterModesWithIdx, { persist = true })
  local event = capabilities.mode.supportedModes(supportWaterHeaterModes, { visibility = { displayed = false } })
  device:emit_event_for_endpoint(ib.endpoint_id, event)
  event = capabilities.mode.supportedArguments(supportWaterHeaterModes, { visibility = { displayed = false } })
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

function AttributeHandlers.water_heater_current_mode_handler(driver, device, ib, response)
  device.log.info(string.format("water_heater_current_mode_handler mode: %s", ib.data.value))
  local supportWaterHeaterModesWithIdx = device:get_field(fields.SUPPORTED_WATER_HEATER_MODES_WITH_IDX) or {}
  local currentMode = ib.data.value
  for i, mode in ipairs(supportWaterHeaterModesWithIdx) do
    if mode[1] == currentMode then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.mode(mode[2]))
      break
    end
  end
end


-- [[ RELATIVE HUMIDITY MEASUREMENT CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.relative_humidity_measured_value_handler(driver, device, ib, response)
  local humidity = math.floor(ib.data.value / 100.0)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(humidity))
end


-- [[ ON OFF CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.on_off_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  end
end

return AttributeHandlers
