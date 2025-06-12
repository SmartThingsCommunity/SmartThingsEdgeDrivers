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
local utils = require "st.utils"
local log = require "log"

local WIND_MODE_MAP = {
  [0] = capabilities.windMode.windMode.sleepWind,
  [1] = capabilities.windMode.windMode.naturalWind
}

local ROCK_MODE_MAP = {
  [0] = capabilities.fanOscillationMode.fanOscillationMode.horizontal,
  [1] = capabilities.fanOscillationMode.fanOscillationMode.vertical,
  [2] = capabilities.fanOscillationMode.fanOscillationMode.swing
}

local AP_DEVICE_TYPE_ID = 0x002D -- Air Purifier
local FAN_DEVICE_TYPE_ID = 0x002B

local MIN_ALLOWED_PERCENT_VALUE = 0
local MAX_ALLOWED_PERCENT_VALUE = 100

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"

local profiling_data = {
  THERMOSTAT_RUNNING_STATE_SUPPORT = "__THERMOSTAT_RUNNING_STATE_SUPPORT"
}

local subscribed_attributes = {
  [capabilities.switch.ID] = {
    clusters.OnOff.attributes.OnOff
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
  [capabilities.fanOscillationMode.ID] = {
    clusters.FanControl.attributes.RockSupport,
    clusters.FanControl.attributes.RockSetting
  },
}

local function get_device_type(driver, device)
  for _, ep in ipairs(device.endpoints) do
    if ep.device_types ~= nil then
      for _, dt in ipairs(ep.device_types) do
        if dt.device_type_id == AP_DEVICE_TYPE_ID then
          return AP_DEVICE_TYPE_ID
        elseif dt.device_type_id == FAN_DEVICE_TYPE_ID then
          return FAN_DEVICE_TYPE_ID
        end
      end
    end
  end
  return false
end

local AIR_QUALITY_MAP = {
  {capabilities.carbonDioxideMeasurement.ID,     "-co2",   clusters.CarbonDioxideConcentrationMeasurement},
  {capabilities.carbonDioxideHealthConcern.ID,   "-co2",   clusters.CarbonDioxideConcentrationMeasurement},
  {capabilities.carbonMonoxideMeasurement.ID,    "-co",    clusters.CarbonMonoxideConcentrationMeasurement},
  {capabilities.carbonMonoxideHealthConcern.ID,  "-co",    clusters.CarbonMonoxideConcentrationMeasurement},
  {capabilities.dustSensor.ID,                   "-pm10",  clusters.Pm10ConcentrationMeasurement},
  {capabilities.dustHealthConcern.ID,            "-pm10",  clusters.Pm10ConcentrationMeasurement},
  {capabilities.fineDustSensor.ID,               "-pm25",  clusters.Pm25ConcentrationMeasurement},
  {capabilities.fineDustHealthConcern.ID,        "-pm25",  clusters.Pm25ConcentrationMeasurement},
  {capabilities.formaldehydeMeasurement.ID,      "-ch2o",  clusters.FormaldehydeConcentrationMeasurement},
  {capabilities.formaldehydeHealthConcern.ID,    "-ch2o",  clusters.FormaldehydeConcentrationMeasurement},
  {capabilities.nitrogenDioxideHealthConcern.ID, "-no2",   clusters.NitrogenDioxideConcentrationMeasurement},
  {capabilities.nitrogenDioxideMeasurement.ID,   "-no2",   clusters.NitrogenDioxideConcentrationMeasurement},
  {capabilities.ozoneHealthConcern.ID,           "-ozone", clusters.OzoneConcentrationMeasurement},
  {capabilities.ozoneMeasurement.ID,             "-ozone", clusters.OzoneConcentrationMeasurement},
  {capabilities.radonHealthConcern.ID,           "-radon", clusters.RadonConcentrationMeasurement},
  {capabilities.radonMeasurement.ID,             "-radon", clusters.RadonConcentrationMeasurement},
  {capabilities.tvocHealthConcern.ID,            "-tvoc",  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement},
  {capabilities.tvocMeasurement.ID,              "-tvoc",  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement},
  {capabilities.veryFineDustHealthConcern.ID,    "-pm1",   clusters.Pm1ConcentrationMeasurement},
  {capabilities.veryFineDustSensor.ID,           "-pm1",   clusters.Pm1ConcentrationMeasurement},
}

local function create_level_measurement_profile(device)
  local meas_name, level_name = "", ""
  for _, details in ipairs(AIR_QUALITY_MAP) do
    local cap_id  = details[1]
    local cluster = details[3]
    if (cap_id:match("HealthConcern$")) then
      local attr_eps = device:get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.LEVEL_INDICATION })
      if #attr_eps > 0 then
        level_name = level_name .. details[2]
      end
    elseif (cap_id:match("Measurement$") or cap_id:match("Sensor$")) then
      local attr_eps = device:get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.NUMERIC_MEASUREMENT })
      if #attr_eps > 0 then
        meas_name = meas_name .. details[2]
      end
    end
  end
  return meas_name, level_name
end

local function create_air_quality_sensor_profile(device)
  local aqs_eps = device:get_endpoints(device, clusters.AirQuality.ID)
  local profile_name = ""
  if #aqs_eps > 0 then
    profile_name = profile_name .. "-aqs"
  end
  local meas_name, level_name = create_level_measurement_profile(device)
  if meas_name ~= "" then
    profile_name = profile_name .. meas_name .. "-meas"
  end
  if level_name ~= "" then
    profile_name = profile_name .. level_name .. "-level"
  end
  return profile_name
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

local function create_air_purifier_profile(device)
  local hepa_filter_eps = device:get_endpoints(device, clusters.HepaFilterMonitoring.ID)
  local ac_filter_eps = device:get_endpoints(device, clusters.ActivatedCarbonFilterMonitoring.ID)
  local fan_eps_seen = false
  local profile_name = "air-purifier"
  if #hepa_filter_eps > 0 then
    profile_name = profile_name .. "-hepa"
  end
  if #ac_filter_eps > 0 then
    profile_name = profile_name .. "-ac"
  end

  local fan_profile = create_fan_profile(device)
  if fan_profile ~= "" then
    fan_eps_seen = true
  end
  fan_profile = string.gsub(fan_profile, "-fan", "")
  profile_name = profile_name .. fan_profile

  return profile_name, fan_eps_seen
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
  if device_type == FAN_DEVICE_TYPE_ID then
    profile_name = create_fan_profile(device)
    profile_name = string.sub(profile_name, 2)
    if profile_name == "fan" then
      profile_name = "fan-generic"
    end

  elseif device_type == AP_DEVICE_TYPE_ID then
    local fan_eps_found
    profile_name, fan_eps_found = create_air_purifier_profile(device)
    if #thermostat_eps > 0 then
      profile_name = profile_name .. "-thermostat"

      if #humidity_eps > 0 then
        profile_name = profile_name .. "-humidity"
      end

      if fan_eps_found then
        profile_name = profile_name .. "-fan"
      end

      local thermostat_modes = create_thermostat_modes_profile(device)
      if thermostat_modes ~= "No Heating nor Cooling Support" then
        profile_name = profile_name .. thermostat_modes
      end

      if not running_state_supported then
        profile_name = profile_name .. "-nostate"
      end

    end
    profile_name = profile_name .. create_air_quality_sensor_profile(device)
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
    local event = capabilities.airConditionerFanMode.supportedAcFanModes(supportedAcFanModes, {visibility = {displayed = false}})
    device:emit_event_for_endpoint(ib.endpoint_id, event)
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
    local event = capabilities.airPurifierFanMode.supportedAirPurifierFanModes(supportedAirPurifierFanModes, {visibility = {displayed = false}})
    device:emit_event_for_endpoint(ib.endpoint_id, event)
  else
    -- Thermostat
    if ib.data.value >= clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO and
      ib.data.value <= clusters.FanControl.attributes.FanModeSequence.OFF_ON_AUTO then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatFanMode.supportedThermostatFanModes(
        {capabilities.thermostatFanMode.thermostatFanMode.auto.NAME, capabilities.thermostatFanMode.thermostatFanMode.on.NAME},
        {visibility = {displayed = false}}
      ))
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatFanMode.supportedThermostatFanModes(
        {capabilities.thermostatFanMode.thermostatFanMode.on.NAME},
        {visibility = {displayed = false}}
      ))
    end
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

local function fan_speed_percent_attr_handler(driver, device, ib, response)
  local speed = 0
  if ib.data.value ~= nil then
    speed = utils.clamp_value(ib.data.value, MIN_ALLOWED_PERCENT_VALUE, MAX_ALLOWED_PERCENT_VALUE)
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
  local event = capabilities.windMode.supportedWindModes(supported_wind_modes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
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

local function rock_support_handler(driver, device, ib, response)
  local supported_rock_modes = {capabilities.fanOscillationMode.fanOscillationMode.off.NAME}
  for mode, rock_mode in pairs(ROCK_MODE_MAP) do
    if ((ib.data.value >> mode) & 1) > 0 then
      table.insert(supported_rock_modes, rock_mode.NAME)
    end
  end
  local event = capabilities.fanOscillationMode.supportedFanOscillationModes(supported_rock_modes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function rock_setting_handler(driver, device, ib, response)
  for index, rock_mode in pairs(ROCK_MODE_MAP) do
    if ((ib.data.value >> index) & 1) > 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, rock_mode())
      return
    end
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanOscillationMode.fanOscillationMode.off())
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
    device:send(clusters.FanControl.attributes.FanMode:write(device, component_to_endpoint(device, cmd.component, clusters.FanControl.ID), fan_mode_id))
  end
end

local function device_init(driver, device)
  device:subscribe()
  device:set_component_to_endpoint_fn(component_to_endpoint)
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
  return device.label:find("전열교환기") ~= nil
end

local ventilator_handler = {
  NAME = "Ventilator Handler",
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
      [clusters.FanControl.ID] = {
        [clusters.FanControl.attributes.FanModeSequence.ID] = fan_mode_sequence_handler,
        [clusters.FanControl.attributes.FanMode.ID] = fan_mode_handler,
        [clusters.FanControl.attributes.PercentCurrent.ID] = fan_speed_percent_attr_handler,
        [clusters.FanControl.attributes.WindSupport.ID] = wind_support_handler,
        [clusters.FanControl.attributes.WindSetting.ID] = wind_setting_handler,
        [clusters.FanControl.attributes.RockSupport.ID] = rock_support_handler,
        [clusters.FanControl.attributes.RockSetting.ID] = rock_setting_handler,
      },
    }
  },
  subscribed_attributes = subscribed_attributes,
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
    [capabilities.airPurifierFanMode.ID] = {
      [capabilities.airPurifierFanMode.commands.setAirPurifierFanMode.NAME] = set_air_purifier_fan_mode
    },
  },
  supported_capabilities = {
    capabilities.switch,
    capabilities.airPurifierFanMode,
  }
}

return ventilator_handler
