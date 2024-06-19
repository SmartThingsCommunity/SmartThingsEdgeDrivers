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
local embedded_cluster_utils = require "embedded-cluster-utils"
local im = require "st.matter.interaction_model"

local MatterDriver = require "st.matter.driver"
local utils = require "st.utils"

-- Include driver-side definitions when lua libs api version is < 10
local version = require "version"
if version.api < 10 then
  clusters.HepaFilterMonitoring = require "HepaFilterMonitoring"
  clusters.ActivatedCarbonFilterMonitoring = require "ActivatedCarbonFilterMonitoring"
  -- new modes add in Matter 1.2
  clusters.Thermostat.types.ThermostatSystemMode.DRY = 0x8
  clusters.Thermostat.types.ThermostatSystemMode.SLEEP = 0x9
end

local THERMOSTAT_MODE_MAP = {
  [clusters.Thermostat.types.ThermostatSystemMode.OFF]            = capabilities.thermostatMode.thermostatMode.off,
  [clusters.Thermostat.types.ThermostatSystemMode.AUTO]           = capabilities.thermostatMode.thermostatMode.auto,
  [clusters.Thermostat.types.ThermostatSystemMode.COOL]           = capabilities.thermostatMode.thermostatMode.cool,
  [clusters.Thermostat.types.ThermostatSystemMode.HEAT]           = capabilities.thermostatMode.thermostatMode.heat,
  [clusters.Thermostat.types.ThermostatSystemMode.EMERGENCY_HEATING] = capabilities.thermostatMode.thermostatMode.emergency_heat,
  [clusters.Thermostat.types.ThermostatSystemMode.PRECOOLING]     = capabilities.thermostatMode.thermostatMode.precooling,
  [clusters.Thermostat.types.ThermostatSystemMode.FAN_ONLY]       = capabilities.thermostatMode.thermostatMode.fanonly,
  [clusters.Thermostat.types.ThermostatSystemMode.DRY]            = capabilities.thermostatMode.thermostatMode.dryair,
  [clusters.Thermostat.types.ThermostatSystemMode.SLEEP]          = capabilities.thermostatMode.thermostatMode.asleep
}

local THERMOSTAT_OPERATING_MODE_MAP = {
  [0]		= capabilities.thermostatOperatingState.thermostatOperatingState.heating,
  [1]		= capabilities.thermostatOperatingState.thermostatOperatingState.cooling,
  [2]		= capabilities.thermostatOperatingState.thermostatOperatingState.fan_only,
  [3]		= capabilities.thermostatOperatingState.thermostatOperatingState.heating,
  [4]		= capabilities.thermostatOperatingState.thermostatOperatingState.cooling,
  [5]		= capabilities.thermostatOperatingState.thermostatOperatingState.fan_only,
  [6]		= capabilities.thermostatOperatingState.thermostatOperatingState.fan_only,
}

local WIND_MODE_MAP = {
  [0]		= capabilities.windMode.windMode.sleepWind,
  [1]		= capabilities.windMode.windMode.naturalWind
}

local RAC_DEVICE_TYPE_ID = 0x0072
local AP_DEVICE_TYPE_ID = 0x002D
local FAN_DEVICE_TYPE_ID = 0x002B

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

local subscribed_attributes = {
  [capabilities.switch.ID] = {
    clusters.OnOff.attributes.OnOff
  },
  [capabilities.temperatureMeasurement.ID] = {
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
    clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
    clusters.TemperatureMeasurement.attributes.MaxMeasuredValue
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
    clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
    clusters.Thermostat.attributes.AbsMinCoolSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit
  },
  [capabilities.thermostatHeatingSetpoint.ID] = {
    clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
    clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit
  },
  [capabilities.airConditionerFanMode.ID] = {
    clusters.FanControl.attributes.FanMode
  },
  [capabilities.airPurifierFanMode.ID] = {
    clusters.FanControl.attributes.FanModeSequence,
    clusters.FanControl.attributes.FanMode
  },
  [capabilities.fanSpeedPercent.ID] = {
    clusters.FanControl.attributes.PercentCurrent
  },
  [capabilities.windMode.ID] = {
    clusters.FanControl.attributes.WindSupport,
    clusters.FanControl.attributes.WindSetting
  },
  [capabilities.battery.ID] = {
    clusters.PowerSource.attributes.BatPercentRemaining
  },
  [capabilities.filterState.ID] = {
    clusters.HepaFilterMonitoring.attributes.Condition,
    clusters.ActivatedCarbonFilterMonitoring.attributes.Condition
  },
  [capabilities.filterStatus.ID] = {
    clusters.HepaFilterMonitoring.attributes.ChangeIndication,
    clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication
  }
}

local function get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

local function set_field_for_endpoint(device, field, endpoint, value, additional_params)
  device:set_field(string.format("%s_%d", field, endpoint), value, additional_params)
end

local function find_default_endpoint(device, cluster)
  local res = device.MATTER_DEFAULT_ENDPOINT
  local eps = embedded_cluster_utils.get_endpoints(device, cluster)
  table.sort(eps)
  for _, v in ipairs(eps) do
    if v ~= 0 then --0 is the matter RootNode endpoint
      return v
    end
  end
  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return res
end

local function component_to_endpoint(device, component_name)
  -- Use the find_default_endpoint function to return the first endpoint that
  -- supports a given cluster.
  if device:supports_capability(capabilities.airPurifierFanMode) then
    -- Fan Control is mandatory for the Air Purifier device type
    return find_default_endpoint(device, clusters.FanControl.ID)
  else
    -- Thermostat is mandatory for Thermostat and Room AC device type
    return find_default_endpoint(device, clusters.Thermostat.ID)
  end
end

local function device_init(driver, device)
  device:subscribe()
  device:set_component_to_endpoint_fn(component_to_endpoint)

  if not device:get_field(setpoint_limit_device_field.MIN_SETPOINT_DEADBAND_CHECKED) then
    local auto_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.AUTOMODE})
    --Query min setpoint deadband if needed
    if #auto_eps ~= 0 and device:get_field(setpoint_limit_device_field.MIN_DEADBAND) == nil then
      local setpoint_limit_read = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
      setpoint_limit_read:merge(clusters.Thermostat.attributes.MinSetpointDeadBand:read())
      device:send(setpoint_limit_read)
    end
    device:set_field(setpoint_limit_device_field.MIN_SETPOINT_DEADBAND_CHECKED, true)
  end
end

local function info_changed(driver, device, event, args)
  --Note this is needed because device:subscribe() does not recalculate
  -- the subscribed attributes each time it is run, that only happens at init.
  -- This will change in the 0.48.x release of the lua libs.
  for cap_id, attributes in pairs(subscribed_attributes) do
    if device:supports_capability_by_id(cap_id) then
      for _, attr in ipairs(attributes) do
        device:add_subscribed_attribute(attr)
      end
    end
  end
  device:subscribe()
end

local function get_device_type(driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == RAC_DEVICE_TYPE_ID then
        return RAC_DEVICE_TYPE_ID
      elseif dt.device_type_id == AP_DEVICE_TYPE_ID then
        return AP_DEVICE_TYPE_ID
      elseif dt.device_type_id == FAN_DEVICE_TYPE_ID then
        return FAN_DEVICE_TYPE_ID
      end
    end
  end
  return false
end

local function do_configure(driver, device)
  local heat_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.HEATING})
  local cool_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.COOLING})
  local thermo_eps = device:get_endpoints(clusters.Thermostat.ID)
  local fan_eps = device:get_endpoints(clusters.FanControl.ID)
  local wind_eps = device:get_endpoints(clusters.FanControl.ID, {feature_bitmap = clusters.FanControl.types.FanControlFeature.WIND})
  local humidity_eps = device:get_endpoints(clusters.RelativeHumidityMeasurement.ID)
  local battery_eps = device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
  -- use get_endpoints for embedded clusters
  local hepa_filter_eps = embedded_cluster_utils.get_endpoints(device, clusters.HepaFilterMonitoring.ID)
  local ac_filter_eps = embedded_cluster_utils.get_endpoints(device, clusters.ActivatedCarbonFilterMonitoring.ID)
  local device_type = get_device_type(driver, device)
  local profile_name = "thermostat"
  --Note: we have not encountered thermostats with multiple endpoints that support the Thermostat cluster
  if device_type == RAC_DEVICE_TYPE_ID then
    device.log.warn_with({hub_logs=true}, "Room Air Conditioner supports only one profile")
  elseif device_type == FAN_DEVICE_TYPE_ID then
    device.log.warn_with({hub_logs=true}, "Fan supports only one profile")
  elseif device_type == AP_DEVICE_TYPE_ID then
    -- currently no profile switching for Air Purifier
    profile_name = "air-purifier"
    if #hepa_filter_eps > 0 and #ac_filter_eps > 0 then
      profile_name = profile_name .. "-hepa" .. "-ac"
    elseif #hepa_filter_eps > 0 then
      profile_name = profile_name .. "-hepa"
    elseif #ac_filter_eps > 0 then
      profile_name = profile_name .. "-ac"
    end
    if #wind_eps > 0 then
      profile_name = profile_name .. "-wind"
    end
    device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({profile = profile_name})
  elseif #thermo_eps == 1 then
    if #humidity_eps > 0 and #fan_eps > 0 then
      profile_name = profile_name .. "-humidity" .. "-fan"
    elseif #humidity_eps > 0 then
      profile_name = profile_name .. "-humidity"
    elseif #fan_eps > 0 then
      profile_name = profile_name .. "-fan"
    end

    if #heat_eps == 0 and #cool_eps == 0 then
      device.log.warn_with({hub_logs=true}, "Thermostat does not support heating or cooling. No matching profile")
      return
    elseif #heat_eps > 0 and #cool_eps == 0 then
      profile_name = profile_name .. "-heating-only"
    elseif #cool_eps > 0 and #heat_eps == 0 then
      profile_name = profile_name .. "-cooling-only"
    end

    -- TODO remove this in favor of reading Thermostat clusters AttributeList attribute
    -- to determine support for ThermostatRunningState
    -- Add nobattery profiles if updated
    profile_name = profile_name .. "-nostate"

    if #battery_eps == 0 then
      profile_name = profile_name .. "-nobattery"
    end

    device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({profile = profile_name})
  elseif #fan_eps == 1 then
    profile_name = "fan"
    device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({profile = profile_name})
  else
    device.log.warn_with({hub_logs=true}, "Device does not support thermostat cluster")
  end
end


local function device_added(driver, device)
  device:send(clusters.Thermostat.attributes.ControlSequenceOfOperation:read(device))
  device:send(clusters.FanControl.attributes.FanModeSequence:read(device))
  device:send(clusters.FanControl.attributes.WindSupport:read(device))
end

local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  end
end

local function temp_event_handler(attribute)
  return function(driver, device, ib, response)
    local temp = ib.data.value / 100.0
    local unit = "C"
    device:emit_event_for_endpoint(ib.endpoint_id, attribute({value = temp, unit = unit}))
  end
end

local temp_attr_handler_factory = function(minOrMax)
  return function(driver, device, ib, response)
    -- Return if no data or RPC version < 4 (unit conversion for temperature
    -- range capability is only supported for RPC >= 4)
    if ib.data.value == nil or version.rpc < 4 then
      return
    end
    local temp = ib.data.value / 100.0
    local unit = "C"
    set_field_for_endpoint(device, minOrMax, ib.endpoint_id, temp)
    local min = get_field_for_endpoint(device, setpoint_limit_device_field.MIN_TEMP, ib.endpoint_id)
    local max = get_field_for_endpoint(device, setpoint_limit_device_field.MAX_TEMP, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = min, maximum = max }, unit = unit }))
        set_field_for_endpoint(device, setpoint_limit_device_field.MIN_TEMP, ib.endpoint_id, nil)
        set_field_for_endpoint(device, setpoint_limit_device_field.MAX_TEMP, ib.endpoint_id, nil)
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min temperature %d that is not lower than the reported max temperature %d", min, max))
      end
    end
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

  local auto = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.auto})
  if #auto > 0 then
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.auto.NAME)
  end

  if ib.data.value <= clusters.Thermostat.attributes.ControlSequenceOfOperation.COOLING_WITH_REHEAT then
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.cool.NAME)
    -- table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.precooling.NAME)
  elseif ib.data.value <= clusters.Thermostat.attributes.ControlSequenceOfOperation.HEATING_WITH_REHEAT then
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.heat.NAME)
    -- table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.emergencyheat.NAME)
  elseif ib.data.value <= clusters.Thermostat.attributes.ControlSequenceOfOperation.COOLING_AND_HEATING_WITH_REHEAT then
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.cool.NAME)
    table.insert(supported_modes, capabilities.thermostatMode.thermostatMode.heat.NAME)
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatMode.supportedThermostatModes(supported_modes))
end

local function min_deadband_limit_handler(driver, device, ib, response)
  local val = ib.data.value / 10.0
  log.info("Setting " .. setpoint_limit_device_field.MIN_DEADBAND .. " to " .. string.format("%s", val))
  device:set_field(setpoint_limit_device_field.MIN_DEADBAND, val, { persist = true })
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
    elseif ib.data.value ~= clusters.FanControl.attributes.FanMode.OFF then -- we don't have an "off" value
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatFanMode.thermostatFanMode.on())
    end
  end
end

local function fan_mode_sequence_handler(driver, device, ib, response)
  if device:supports_capability_by_id(capabilities.airConditionerFanMode.ID) then
    -- Room Air Conditioner
    local supportedAcFanModes
    if ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH then
      supportedAcFanModes = {
        "off",
        "low",
        "medium",
        "high"
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH then
      supportedAcFanModes = {
        "off",
        "low",
        "high"
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO then
      supportedAcFanModes = {
        "off",
        "low",
        "medium",
        "high",
        "auto"
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH_AUTO then
      supportedAcFanModes = {
        "off",
        "low",
        "high",
        "auto"
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_ON_AUTO then
      supportedAcFanModes = {
        "off",
        "high",
        "auto"
      }
    else
      supportedAcFanModes = {
        "off",
        "high"
      }
    end
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airConditionerFanMode.supportedAcFanModes(supportedAcFanModes))
  elseif device:supports_capability_by_id(capabilities.airPurifierFanMode.ID) then
    -- Air Purifier
    local supportedAirPurifierFanModes
    if ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH then
      supportedAirPurifierFanModes = {
        capabilities.airPurifierFanMode.airPurifierFanMode.off.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.medium.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH then
      supportedAirPurifierFanModes = {
        capabilities.airPurifierFanMode.airPurifierFanMode.off.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO then
      supportedAirPurifierFanModes = {
        capabilities.airPurifierFanMode.airPurifierFanMode.off.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.medium.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.auto.NAME
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH_AUTO then
      supportedAirPurifierFanModes = {
        capabilities.airPurifierFanMode.airPurifierFanMode.off.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.auto.NAME
      }
    elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_ON_AUTO then
      supportedAirPurifierFanModes = {
        capabilities.airPurifierFanMode.airPurifierFanMode.off.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.auto.NAME
      }
    else
      supportedAirPurifierFanModes = {
        capabilities.airPurifierFanMode.airPurifierFanMode.off.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME
      }
    end
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.supportedAirPurifierFanModes(supportedAirPurifierFanModes))
  else
    -- Thermostat
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
end

local function fan_speed_percent_attr_handler(driver, device, ib, response)
  local speed = 0
  if ib.data.value ~= nil then
    speed = ib.data.value
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanSpeedPercent.percent(speed))
end

local function wind_support_handler(driver, device, ib, response)
  local supported_wind_modes = {capabilities.windMode.windMode.noWind.NAME}
  for mode, wind_mode in pairs(WIND_MODE_MAP) do
    if ((ib.data.value >> mode) & 1) > 0 then
      table.insert(supported_wind_modes, wind_mode.NAME)
    end
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windMode.supportedWindModes(supported_wind_modes))
end

local function wind_setting_handler(driver, device, ib, response)
  for index, wind_mode in pairs(WIND_MODE_MAP) do
    if ((ib.data.value >> index) & 1) > 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, wind_mode())
      return
    end
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windMode.windMode.noWind())
end

local function hepa_filter_condition_handler(driver, device, ib, response)
  local component = device.profile.components["hepaFilter"]
  local condition = ib.data.value
  device:emit_component_event(component, capabilities.filterState.filterLifeRemaining(condition))
end

local function hepa_filter_change_indication_handler(driver, device, ib, response)
  local component = device.profile.components["hepaFilter"]
  if ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.OK then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.WARNING then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.CRITICAL then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.replace())
  end
end

local function activated_carbon_filter_condition_handler(driver, device, ib, response)
  local component = device.profile.components["activatedCarbonFilter"]
  local condition = ib.data.value
  device:emit_component_event(component, capabilities.filterState.filterLifeRemaining(condition))
end

local function activated_carbon_filter_change_indication_handler(driver, device, ib, response)
  local component = device.profile.components["activatedCarbonFilter"]
  if ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.OK then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.WARNING then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.CRITICAL then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.replace())
  end
end

local function handle_switch_on(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.On(device, endpoint_id)
  device:send(req)
end

local function handle_switch_off(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
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
    device:send(clusters.Thermostat.attributes.SystemMode:write(device, device:component_to_endpoint(cmd.component), mode_id))
  end
end

local thermostat_mode_setter = function(mode_name)
  return function(driver, device, cmd)
    return set_thermostat_mode(driver, device, {component = cmd.component, args = {mode = mode_name}})
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

local heating_setpoint_limit_handler_factory = function(minOrMax)
  return function(driver, device, ib, response)
    -- Return if no data or RPC version < 4 (unit conversion for heating setpoint
    -- range capability is only supported for RPC >= 4)
    if ib.data.value == nil or version.rpc < 4 then
      return
    end
    local val = ib.data.value / 100.0
    if val >= 40 then -- assume this is a fahrenheit value
      val = utils.f_to_c(val)
    end
    device:set_field(minOrMax, val)
    local min = device:get_field(setpoint_limit_device_field.MIN_HEAT)
    local max = device:get_field(setpoint_limit_device_field.MAX_HEAT)
    if min ~= nil and max ~= nil then
      if min < max then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatHeatingSetpoint.heatingSetpointRange({ value = { minimum = min, maximum = max }, unit = "C" }))
        set_field_for_endpoint(device, setpoint_limit_device_field.MIN_HEAT, ib.endpoint_id, nil)
        set_field_for_endpoint(device, setpoint_limit_device_field.MAX_HEAT, ib.endpoint_id, nil)
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min heating setpoint %d that is not lower than the reported max %d", min, max))
      end
    end
  end
end

local cooling_setpoint_limit_handler_factory = function(minOrMax)
  return function(driver, device, ib, response)
    -- Return if no data or RPC version < 4 (unit conversion for cooling setpoint
    -- range capability is only supported for RPC >= 4)
    if ib.data.value == nil or version.rpc < 4 then
      return
    end
    local val = ib.data.value / 100.0
    if val >= 40 then -- assume this is a fahrenheit value
      val = utils.f_to_c(val)
    end
    device:set_field(minOrMax, val)
    local min = device:get_field(setpoint_limit_device_field.MIN_COOL)
    local max = device:get_field(setpoint_limit_device_field.MAX_COOL)
    if min ~= nil and max ~= nil then
      if min < max then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatCoolingSetpoint.coolingSetpointRange({ value = { minimum = min, maximum = max }, unit = "C" }))
        set_field_for_endpoint(device, setpoint_limit_device_field.MIN_COOL, ib.endpoint_id, nil)
        set_field_for_endpoint(device, setpoint_limit_device_field.MAX_COOL, ib.endpoint_id, nil)
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min cooling setpoint %d that is not lower than the reported max %d", min, max))
      end
    end
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
    device:send(clusters.FanControl.attributes.FanMode:write(device, device:component_to_endpoint(cmd.component), fan_mode_id))
  end
end

local function set_air_purifier_fan_mode(driver, device, cmd)
  local fan_mode_id
  if cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.sleep.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.quiet.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.windFree.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.medium.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.MEDIUM
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.HIGH
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.auto.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.AUTO
  else
    fan_mode_id = clusters.FanControl.attributes.FanMode.OFF
  end
  if fan_mode_id then
    device:send(clusters.FanControl.attributes.FanMode:write(device, device:component_to_endpoint(cmd.component), fan_mode_id))
  end
end

local function set_fan_speed_percent(driver, device, cmd)
  local speed = math.floor(cmd.args.percent)
  device:send(clusters.FanControl.attributes.PercentSetting:write(device, device:component_to_endpoint(cmd.component), speed))
end

local function set_wind_mode(driver, device, cmd)
  local wind_mode = 0
  if cmd.args.windMode == capabilities.windMode.windMode.sleepWind.NAME then
    wind_mode = clusters.FanControl.types.WindSupportMask.SLEEP_WIND
  elseif cmd.args.windMode == capabilities.windMode.windMode.naturalWind.NAME then
    wind_mode = clusters.FanControl.types.WindSupportMask.NATURAL_WIND
  end
  device:send(clusters.FanControl.attributes.WindSetting:write(device, device:component_to_endpoint(cmd.component), wind_mode))
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
    infoChanged = info_changed,
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.Thermostat.ID] = {
        [clusters.Thermostat.attributes.LocalTemperature.ID] = temp_event_handler(capabilities.temperatureMeasurement.temperature),
        [clusters.Thermostat.attributes.OccupiedCoolingSetpoint.ID] = temp_event_handler(capabilities.thermostatCoolingSetpoint.coolingSetpoint),
        [clusters.Thermostat.attributes.OccupiedHeatingSetpoint.ID] = temp_event_handler(capabilities.thermostatHeatingSetpoint.heatingSetpoint),
        [clusters.Thermostat.attributes.SystemMode.ID] = system_mode_handler,
        [clusters.Thermostat.attributes.ThermostatRunningState.ID] = running_state_handler,
        [clusters.Thermostat.attributes.ControlSequenceOfOperation.ID] = sequence_of_operation_handler,
        [clusters.Thermostat.attributes.AbsMinHeatSetpointLimit.ID] = heating_setpoint_limit_handler_factory(setpoint_limit_device_field.MIN_HEAT),
        [clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit.ID] = heating_setpoint_limit_handler_factory(setpoint_limit_device_field.MAX_HEAT),
        [clusters.Thermostat.attributes.AbsMinCoolSetpointLimit.ID] = cooling_setpoint_limit_handler_factory(setpoint_limit_device_field.MIN_COOL),
        [clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit.ID] = cooling_setpoint_limit_handler_factory(setpoint_limit_device_field.MAX_COOL),
        [clusters.Thermostat.attributes.MinSetpointDeadBand.ID] = min_deadband_limit_handler,
      },
      [clusters.FanControl.ID] = {
        [clusters.FanControl.attributes.FanModeSequence.ID] = fan_mode_sequence_handler,
        [clusters.FanControl.attributes.FanMode.ID] = fan_mode_handler,
        [clusters.FanControl.attributes.PercentCurrent.ID] = fan_speed_percent_attr_handler,
        [clusters.FanControl.attributes.WindSupport.ID] = wind_support_handler,
        [clusters.FanControl.attributes.WindSetting.ID] = wind_setting_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler(capabilities.temperatureMeasurement.temperature),
        [clusters.TemperatureMeasurement.attributes.MinMeasuredValue.ID] = temp_attr_handler_factory(setpoint_limit_device_field.MIN_TEMP),
        [clusters.TemperatureMeasurement.attributes.MaxMeasuredValue.ID] = temp_attr_handler_factory(setpoint_limit_device_field.MAX_TEMP),
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = humidity_attr_handler
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = battery_percent_remaining_attr_handler
      },
      [clusters.HepaFilterMonitoring.ID] = {
        [clusters.HepaFilterMonitoring.attributes.Condition.ID] = hepa_filter_condition_handler,
        [clusters.HepaFilterMonitoring.attributes.ChangeIndication.ID] = hepa_filter_change_indication_handler
      },
      [clusters.ActivatedCarbonFilterMonitoring.ID] = {
        [clusters.ActivatedCarbonFilterMonitoring.attributes.Condition.ID] = activated_carbon_filter_condition_handler,
        [clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.ID] = activated_carbon_filter_change_indication_handler
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
    },
    [capabilities.airConditionerFanMode.ID] = {
      [capabilities.airConditionerFanMode.commands.setFanMode.NAME] = set_fan_mode,
    },
    [capabilities.airPurifierFanMode.ID] = {
      [capabilities.airPurifierFanMode.commands.setAirPurifierFanMode.NAME] = set_air_purifier_fan_mode
    },
    [capabilities.fanSpeedPercent.ID] = {
      [capabilities.fanSpeedPercent.commands.setPercent.NAME] = set_fan_speed_percent,
    },
    [capabilities.windMode.ID] = {
      [capabilities.windMode.commands.setWindMode.NAME] = set_wind_mode,
    }
  },
  supported_capabilities = {
    capabilities.thermostatMode,
    capabilities.thermostatHeatingSetpoint,
    capabilities.thermostatCoolingSetpoint,
    capabilities.thermostatFanMode,
    capabilities.thermostatOperatingState,
    capabilities.airConditionerFanMode,
    capabilities.fanSpeedPercent,
    capabilities.airPurifierFanMode,
    capabilities.windMode,
    capabilities.battery,
    capabilities.filterState,
    capabilities.filterStatus
  },
}

local matter_driver = MatterDriver("matter-thermostat", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()