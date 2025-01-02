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
local lua_socket = require "socket"
local utils = require "st.utils"
local device_lib = require "st.device"
local embedded_cluster_utils = require "embedded-cluster-utils"

-- This can be removed once LuaLibs supports the PressureMeasurement cluster
if not pcall(function(cluster) return clusters[cluster] end,
             "PressureMeasurement") then
  clusters.PressureMeasurement = require "PressureMeasurement"
end

-- Include driver-side definitions when lua libs api version is < 10
local version = require "version"
if version.api < 10 then
  clusters.AirQuality = require "AirQuality"
  clusters.CarbonMonoxideConcentrationMeasurement = require "CarbonMonoxideConcentrationMeasurement"
  clusters.CarbonDioxideConcentrationMeasurement = require "CarbonDioxideConcentrationMeasurement"
  clusters.FormaldehydeConcentrationMeasurement = require "FormaldehydeConcentrationMeasurement"
  clusters.NitrogenDioxideConcentrationMeasurement = require "NitrogenDioxideConcentrationMeasurement"
  clusters.OzoneConcentrationMeasurement = require "OzoneConcentrationMeasurement"
  clusters.Pm1ConcentrationMeasurement = require "Pm1ConcentrationMeasurement"
  clusters.Pm10ConcentrationMeasurement = require "Pm10ConcentrationMeasurement"
  clusters.Pm25ConcentrationMeasurement = require "Pm25ConcentrationMeasurement"
  clusters.RadonConcentrationMeasurement = require "RadonConcentrationMeasurement"
  clusters.SmokeCoAlarm = require "SmokeCoAlarm"
  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement = require "TotalVolatileOrganicCompoundsConcentrationMeasurement"
end

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.BooleanStateConfiguration = require "BooleanStateConfiguration"
end

local TEMP_BOUND_RECEIVED = "__temp_bound_received"
local TEMP_MIN = "__temp_min"
local TEMP_MAX = "__temp_max"

local HUE_MANUFACTURER_ID = 0x100B

local function get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

local function set_field_for_endpoint(device, field, endpoint, value, additional_params)
  device:set_field(string.format("%s_%d", field, endpoint), value, additional_params)
end

local BOOLEAN_DEVICE_TYPE_INFO = {
  ["RAIN_SENSOR"] = { id = 0x0044, sensitivity_preference = "rainSensitivity", sensitivity_max = "rainMax" },
  ["WATER_FREEZE_DETECTOR"] = { id = 0x0041, sensitivity_preference = "freezeSensitivity", sensitivity_max = "freezeMax" },
  ["WATER_LEAK_DETECTOR"] = { id = 0x0043, sensitivity_preference = "leakSensitivity", sensitivity_max = "leakMax" },
  ["CONTACT_SENSOR"] = { id = 0x0015, sensitivity_preference = "N/A", sensitivity_max = "N/A" },
}

local ORDERED_DEVICE_TYPE_INFO = {
  "RAIN_SENSOR",
  "WATER_FREEZE_DETECTOR",
  "WATER_LEAK_DETECTOR",
  "CONTACT_SENSOR"
}

local function set_boolean_device_type_per_endpoint(driver, device)
  for _, ep in ipairs(device.endpoints) do
      for _, dt in ipairs(ep.device_types) do
          for dt_name, info in pairs(BOOLEAN_DEVICE_TYPE_INFO) do
              if dt.device_type_id == info.id then
                  device:set_field(dt_name, ep.endpoint_id)
                  device:send(clusters.BooleanStateConfiguration.attributes.SupportedSensitivityLevels:read(device, ep.endpoint_id))
              end
          end
      end
  end
end

local function supports_battery_percentage_remaining(device)
  local battery_eps = device:get_endpoints(clusters.PowerSource.ID,
          {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
  -- Hue devices support the PowerSource cluster but don't support reporting battery percentage remaining
  if #battery_eps > 0 and device.manufacturer_info.vendor_id ~= HUE_MANUFACTURER_ID then
    return true
  end
  return false
end

local function supports_sensitivity_preferences(device)
  local preference_names = ""
  local sensitivity_eps = embedded_cluster_utils.get_endpoints(device, clusters.BooleanStateConfiguration.ID,
    {feature_bitmap = clusters.BooleanStateConfiguration.types.Feature.SENSITIVITY_LEVEL})
  if sensitivity_eps and #sensitivity_eps > 0 then
    for _, dt_name in ipairs(ORDERED_DEVICE_TYPE_INFO) do
      for _, sensitivity_ep in pairs(sensitivity_eps) do
        if device:get_field(dt_name) == sensitivity_ep and BOOLEAN_DEVICE_TYPE_INFO[dt_name].sensitivity_preference ~= "N/A" then
          preference_names = preference_names .. "-" .. BOOLEAN_DEVICE_TYPE_INFO[dt_name].sensitivity_preference
        end
      end
    end
  end
  return preference_names
end

local function device_added(driver, device)
  set_boolean_device_type_per_endpoint(driver, device)
end

local function do_configure(driver, device)
  local profile_name = ""

  if device:supports_capability(capabilities.motionSensor) then
    profile_name = profile_name .. "-motion"
  end

  if device:supports_capability(capabilities.contactSensor) then
    profile_name = profile_name .. "-contact"
  end

  if device:supports_capability(capabilities.illuminanceMeasurement) then
    profile_name = profile_name .. "-illuminance"
  end

  if device:supports_capability(capabilities.temperatureMeasurement) then
    profile_name = profile_name .. "-temperature"
  end

  if device:supports_capability(capabilities.relativeHumidityMeasurement) then
    profile_name = profile_name .. "-humidity"
  end

  if device:supports_capability(capabilities.atmosphericPressureMeasurement) then
    profile_name = profile_name .. "-pressure"
  end

  if device:supports_capability(capabilities.rainSensor) then
    profile_name = profile_name .. "-rain"
  end

  if device:supports_capability(capabilities.temperatureAlarm) then
    profile_name = profile_name .. "-freeze"
  end

  if device:supports_capability(capabilities.waterSensor) then
    profile_name = profile_name .. "-leak"
  end

  if device:supports_capability(capabilities.button) then
    local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
    profile_name = profile_name .. string.format("-%dbutton", #button_eps)
  end

  if supports_battery_percentage_remaining(device) then
    profile_name = profile_name .. "-battery"
  end

  if device:supports_capability(capabilities.hardwareFault) then
    profile_name = profile_name .. "-fault"
  end

  local concatenated_preferences = supports_sensitivity_preferences(device)
  profile_name = profile_name .. concatenated_preferences

  -- remove leading "-"
  profile_name = string.sub(profile_name, 2)

  device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
  device:try_update_metadata({profile = profile_name})
end

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
local START_BUTTON_PRESS = "__start_button_press"
local TIMEOUT_THRESHOLD = 10 --arbitrary timeout
local HELD_THRESHOLD = 1

-- Some switches will send a MultiPressComplete event as part of a long press sequence. Normally the driver will create a
-- button capability event on receipt of MultiPressComplete, but in this case that would result in an extra event because
-- the "held" capability event is generated when the LongPress event is received. The IGNORE_NEXT_MPC flag is used
-- to tell the driver to ignore MultiPressComplete if it is received after a long press to avoid this extra event.
local IGNORE_NEXT_MPC = "__ignore_next_mpc"

-- These are essentially storing the supported features of a given endpoint
-- TODO: add an is_feature_supported_for_endpoint function to matter.device that takes an endpoint
local EMULATE_HELD = "__emulate_held" -- for non-MSR (MomentarySwitchRelease) devices we can emulate this on the software side
local SUPPORTS_MULTI_PRESS = "__multi_button" -- for MSM devices (MomentarySwitchMultiPress), create an event on receipt of MultiPressComplete

--helper function to create list of multi press values
local function create_multi_press_values_list(size, supportsHeld)
  local list = {"pushed", "double"}
  if supportsHeld then table.insert(list, "held") end
  -- add multi press values of 3 or greater to the list
  for i=3, size do
    table.insert(list, string.format("pushed_%dx", i))
  end
  return list
end

local function tbl_contains(array, value)
  for _, element in ipairs(array) do
    if element == value then
      return true
    end
  end
  return false
end

local function emulate_held_event(device, ep)
  local now = lua_socket.gettime()
  local press_init = get_field_for_endpoint(device, START_BUTTON_PRESS, ep) or now -- if we don't have an init time, assume instant release
  if (now - press_init) < TIMEOUT_THRESHOLD then
    if (now - press_init) > HELD_THRESHOLD then
      device:emit_event_for_endpoint(ep, capabilities.button.button.held({state_change = true}))
    else
      device:emit_event_for_endpoint(ep, capabilities.button.button.pushed({state_change = true}))
    end
  end
  set_field_for_endpoint(device, START_BUTTON_PRESS, ep, nil, {persist = false})
end

local function max_press_handler(driver, device, ib, response)
  local max = ib.data.value or 1 --get max number of presses
  device.log.debug("Device supports "..max.." presses")
  -- capability only supports up to 6 presses
  if max > 6 then
    log.info("Device supports more than 6 presses")
    max = 6
  end
  local MSL = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS})
  local supportsHeld = tbl_contains(MSL, ib.endpoint_id)
  local values = create_multi_press_values_list(max, supportsHeld)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.supportedButtonValues(values, {visibility = {displayed = false}}))
end

local function configure_buttons(device)
  if device.network_type ~= device_lib.NETWORK_TYPE_CHILD then
    local MS = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
    local MSR = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_RELEASE})
    device.log.debug(#MSR.." momentary switch release endpoints")
    local MSL = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS})
    device.log.debug(#MSL.." momentary switch long press endpoints")
    local MSM = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS})
    device.log.debug(#MSM.." momentary switch multi press endpoints")
    for _, ep in ipairs(MS) do
      local supportedButtonValues_event = capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})
      -- this ordering is important, as MSL & MSM devices must also support MSR
      if tbl_contains(MSM, ep) then
        -- ask the device to tell us its max number of presses
        device.log.debug("sending multi press max read")
        device:send(clusters.Switch.attributes.MultiPressMax:read(device, ep))
        set_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ep, true, {persist = true})
        supportedButtonValues_event = nil -- deferred until max press handler
      end

      if supportedButtonValues_event then
        device:emit_event_for_endpoint(ep, supportedButtonValues_event)
      end
      device:emit_event_for_endpoint(ep, capabilities.button.button.pushed({state_change = false}))
    end
  end
end

local function initialize_button(driver, device)
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  table.sort(button_eps)

  local component_map = {}
  local current_component_number = 1
  for _, ep in ipairs(button_eps) do
    component_map[string.format("button%d", current_component_number)] = ep
    current_component_number = current_component_number + 1
  end
  device:set_field(COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
  configure_buttons(device)
end

local function endpoint_to_component(device, ep)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  for component, endpoint in pairs(map) do
    if endpoint == ep then
      return component
    end
  end
  return "main"
end

local function device_init(driver, device)
  log.info("device init")
  if device:supports_capability(capabilities.button) then
    initialize_button(driver, device)
    device:set_endpoint_to_component_fn(endpoint_to_component)
  end
  device:subscribe()
end

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    device:subscribe()
    set_boolean_device_type_per_endpoint(driver, device)
  end
  if not device.preferences then
    return
  end
  for dt_name, info in pairs(BOOLEAN_DEVICE_TYPE_INFO) do
    local dt_ep = device:get_field(dt_name)
    if dt_ep and info.sensitivity_preference and (device.preferences[info.sensitivity_preference] ~= args.old_st_store.preferences[info.sensitivity_preference]) then
      local sensitivity_preference = device.preferences[info.sensitivity_preference]
      if sensitivity_preference == "2" then -- high
        local max_sensitivity_level = device:get_field(info.sensitivity_max) - 1
        device:send(clusters.BooleanStateConfiguration.attributes.CurrentSensitivityLevel:write(device, dt_ep, max_sensitivity_level))
      elseif sensitivity_preference == "1" then -- medium
        local medium_sensitivity_level = math.floor((device:get_field(info.sensitivity_max) + 1) / 2)
        device:send(clusters.BooleanStateConfiguration.attributes.CurrentSensitivityLevel:write(device, dt_ep, medium_sensitivity_level))
      elseif sensitivity_preference == "0" then -- low
        local min_sensitivity_level = 0
        device:send(clusters.BooleanStateConfiguration.attributes.CurrentSensitivityLevel:write(device, dt_ep, min_sensitivity_level))
      end
    end
  end
end

local function illuminance_attr_handler(driver, device, ib, response)
  local lux = math.floor(10 ^ ((ib.data.value - 1) / 10000))
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.illuminanceMeasurement.illuminance(lux))
end

local function temperature_attr_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local temp = measured_value / 100.0
    local unit = "C"
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperature({value = temp, unit = unit}))
  end
end

local temp_attr_handler_factory = function(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local temp = ib.data.value / 100.0
    local unit = "C"
    set_field_for_endpoint(device, TEMP_BOUND_RECEIVED..minOrMax, ib.endpoint_id, temp)
    local min = get_field_for_endpoint(device, TEMP_BOUND_RECEIVED..TEMP_MIN, ib.endpoint_id)
    local max = get_field_for_endpoint(device, TEMP_BOUND_RECEIVED..TEMP_MAX, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        -- Only emit the capability for RPC version >= 5 (unit conversion for
        -- temperature range capability is only supported for RPC >= 5)
        if version.rpc >= 5 then
          device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = min, maximum = max }, unit = unit }))
        end
        set_field_for_endpoint(device, TEMP_BOUND_RECEIVED..TEMP_MIN, ib.endpoint_id, nil)
        set_field_for_endpoint(device, TEMP_BOUND_RECEIVED..TEMP_MAX, ib.endpoint_id, nil)
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min temperature %d that is not lower than the reported max temperature %d", min, max))
      end
    end
  end
end

local function humidity_attr_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local humidity = utils.round(measured_value / 100.0)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(humidity))
  end
end

local BOOLEAN_CAP_EVENT_MAP = {
  [true] = {
      ["WATER_FREEZE_DETECTOR"] = capabilities.temperatureAlarm.temperatureAlarm.freeze(),
      ["WATER_LEAK_DETECTOR"] = capabilities.waterSensor.water.wet(),
      ["RAIN_SENSOR"] = capabilities.rainSensor.rain.detected(),
      ["CONTACT_SENSOR"] =  capabilities.contactSensor.contact.closed(),
  },
  [false] = {
      ["WATER_FREEZE_DETECTOR"] = capabilities.temperatureAlarm.temperatureAlarm.cleared(),
      ["WATER_LEAK_DETECTOR"] = capabilities.waterSensor.water.dry(),
      ["RAIN_SENSOR"] = capabilities.rainSensor.rain.undetected(),
      ["CONTACT_SENSOR"] =  capabilities.contactSensor.contact.open(),
  }
}

local function boolean_attr_handler(driver, device, ib, response)
  local name
  for dt_name, _ in pairs(BOOLEAN_DEVICE_TYPE_INFO) do
      local dt_ep_id = device:get_field(dt_name)
      if ib.endpoint_id == dt_ep_id then
          name = dt_name
          break
      end
  end
  if name then
    device:emit_event_for_endpoint(ib.endpoint_id, BOOLEAN_CAP_EVENT_MAP[ib.data.value][name])
  elseif device:supports_capability(capabilities.contactSensor) then
    -- The generic case where no device type has been specified but the profile uses this capability.
      device:emit_event_for_endpoint(ib.endpoint_id, BOOLEAN_CAP_EVENT_MAP[ib.data.value]["CONTACT_SENSOR"])
  else
    log.error("No Boolean device type found on an endpoint, BooleanState handler aborted")
  end
end

local function supported_sensitivities_handler(driver, device, ib, response)
  if not ib.data.value then
    return
  end

  for dt_name, info in pairs(BOOLEAN_DEVICE_TYPE_INFO) do
    if device:get_field(dt_name) == ib.endpoint_id then
      device:set_field(info.sensitivity_max, ib.data.value)
    end
  end
end

local function sensor_fault_handler(driver, device, ib, response)
  if ib.data.value > 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.hardwareFault.hardwareFault.detected())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.hardwareFault.hardwareFault.clear())
  end
end

local function battery_percent_remaining_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

local function occupancy_attr_handler(driver, device, ib, response)
  device:emit_event(ib.data.value == 0x01 and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
end

local function pressure_attr_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local kPa = utils.round(measured_value / 10.0)
    local unit = "kPa"
    device:emit_event(capabilities.atmosphericPressureMeasurement.atmosphericPressure({value = kPa, unit = unit}))
  end
end

local function initial_press_event_handler(driver, device, ib, response)
  if get_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
    -- Receipt of an InitialPress event means we do not want to ignore the next MultiPressComplete event
    -- or else we would potentially not create the expected button capability event
    set_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id, nil)
  end
end

-- if the device distinguishes a long press event, it will always be a "held"
-- there's also a "long release" event, but this event is required to come first
local function long_press_event_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.held({state_change = true}))
  if get_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
    -- Ignore the next MultiPressComplete event if it is sent as part of this "long press" event sequence
    set_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id, true)
  end
end

local function short_release_event_handler(driver, device, ib, response)
  if not get_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
    if get_field_for_endpoint(device, EMULATE_HELD, ib.endpoint_id) then
      emulate_held_event(device, ib.endpoint_id)
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.pushed({state_change = true}))
    end
  end
end

local function multi_press_complete_event_handler(driver, device, ib, response)
  -- in the case of multiple button presses
  -- emit number of times, multiple presses have been completed
  if ib.data and not get_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id) then
    local press_value = ib.data.elements.total_number_of_presses_counted.value
    --capability only supports up to 6 presses
    if press_value < 7 then
      local button_event = capabilities.button.button.pushed({state_change = true})
      if press_value == 2 then
        button_event = capabilities.button.button.double({state_change = true})
      elseif press_value > 2 then
        button_event = capabilities.button.button(string.format("pushed_%dx", press_value), {state_change = true})
      end

      device:emit_event_for_endpoint(ib.endpoint_id, button_event)
    else
      log.info(string.format("Number of presses (%d) not supported by capability", press_value))
    end
  end
  set_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id, nil)
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed,
    doConfigure = do_configure,
    added = device_added,
  },
  matter_handlers = {
    attr = {
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = humidity_attr_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temperature_attr_handler,
        [clusters.TemperatureMeasurement.attributes.MinMeasuredValue.ID] = temp_attr_handler_factory(TEMP_MIN),
        [clusters.TemperatureMeasurement.attributes.MaxMeasuredValue.ID] = temp_attr_handler_factory(TEMP_MAX),
      },
      [clusters.IlluminanceMeasurement.ID] = {
        [clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID] = illuminance_attr_handler
      },
      [clusters.BooleanState.ID] = {
        [clusters.BooleanState.attributes.StateValue.ID] = boolean_attr_handler
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = battery_percent_remaining_attr_handler,
      },
      [clusters.OccupancySensing.ID] = {
        [clusters.OccupancySensing.attributes.Occupancy.ID] = occupancy_attr_handler,
      },
      [clusters.PressureMeasurement.ID] = {
        [clusters.PressureMeasurement.attributes.MeasuredValue.ID] = pressure_attr_handler,
      },
      [clusters.BooleanStateConfiguration.ID] = {
        [clusters.BooleanStateConfiguration.attributes.SensorFault.ID] = sensor_fault_handler,
        [clusters.BooleanStateConfiguration.attributes.SupportedSensitivityLevels.ID] = supported_sensitivities_handler,
      },
      [clusters.Switch.ID] = {
        [clusters.Switch.attributes.MultiPressMax.ID] = max_press_handler
      }
    },
    event = {
      [clusters.Switch.ID] = {
        [clusters.Switch.events.InitialPress.ID] = initial_press_event_handler,
        [clusters.Switch.events.LongPress.ID] = long_press_event_handler,
        [clusters.Switch.events.ShortRelease.ID] = short_release_event_handler,
        [clusters.Switch.events.MultiPressComplete.ID] = multi_press_complete_event_handler
      }
    },
  },
  -- TODO Once capabilities all have default handlers move this info there, and
  -- use `supported_capabilities`
  subscribed_attributes = {
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.TemperatureMeasurement.attributes.MeasuredValue,
      clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
      clusters.TemperatureMeasurement.attributes.MaxMeasuredValue
    },
    [capabilities.illuminanceMeasurement.ID] = {
      clusters.IlluminanceMeasurement.attributes.MeasuredValue
    },
    [capabilities.motionSensor.ID] = {
      clusters.OccupancySensing.attributes.Occupancy
    },
    [capabilities.contactSensor.ID] = {
      clusters.BooleanState.attributes.StateValue
    },
    [capabilities.battery.ID] = {
      clusters.PowerSource.attributes.BatPercentRemaining
    },
    [capabilities.atmosphericPressureMeasurement.ID] = {
      clusters.PressureMeasurement.attributes.MeasuredValue
    },
    [capabilities.airQualityHealthConcern.ID] = {
      clusters.AirQuality.attributes.AirQuality
    },
    [capabilities.carbonMonoxideMeasurement.ID] = {
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.carbonMonoxideHealthConcern.ID] = {
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.carbonDioxideMeasurement.ID] = {
      clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.carbonDioxideHealthConcern.ID] = {
      clusters.CarbonDioxideConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.nitrogenDioxideMeasurement.ID] = {
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasurementUnit
    },
    [capabilities.nitrogenDioxideHealthConcern.ID] = {
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.ozoneMeasurement.ID] = {
      clusters.OzoneConcentrationMeasurement.attributes.MeasuredValue,
      clusters.OzoneConcentrationMeasurement.attributes.MeasurementUnit
    },
    [capabilities.ozoneHealthConcern.ID] = {
      clusters.OzoneConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.formaldehydeMeasurement.ID] = {
      clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue,
      clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.formaldehydeHealthConcern.ID] = {
      clusters.FormaldehydeConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.veryFineDustSensor.ID] = {
      clusters.Pm1ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm1ConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.veryFineDustHealthConcern.ID] = {
      clusters.Pm1ConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.fineDustHealthConcern.ID] = {
      clusters.Pm25ConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.fineDustSensor.ID] = {
      clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.dustSensor.ID] = {
      clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit,
      clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.dustHealthConcern.ID] = {
      clusters.Pm10ConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.radonMeasurement.ID] = {
      clusters.RadonConcentrationMeasurement.attributes.MeasuredValue,
      clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.radonHealthConcern.ID] = {
      clusters.RadonConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.tvocMeasurement.ID] = {
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue,
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.tvocHealthConcern.ID] = {
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.smokeDetector.ID] = {
      clusters.SmokeCoAlarm.attributes.SmokeState,
      clusters.SmokeCoAlarm.attributes.TestInProgress,
    },
    [capabilities.carbonMonoxideDetector.ID] = {
      clusters.SmokeCoAlarm.attributes.COState,
      clusters.SmokeCoAlarm.attributes.TestInProgress,
    },
    [capabilities.hardwareFault.ID] = {
      clusters.SmokeCoAlarm.attributes.HardwareFaultAlert,
      clusters.BooleanStateConfiguration.attributes.SensorFault,
    },
    [capabilities.batteryLevel.ID] = {
      clusters.SmokeCoAlarm.attributes.BatteryAlert,
    },
    [capabilities.waterSensor.ID] = {
        clusters.BooleanState.attributes.StateValue,
    },
    [capabilities.temperatureAlarm.ID] = {
        clusters.BooleanState.attributes.StateValue,
    },
    [capabilities.rainSensor.ID] = {
        clusters.BooleanState.attributes.StateValue,
    },
  },
  subscribed_events = {
    [capabilities.button.ID] = {
      clusters.Switch.events.InitialPress,
      clusters.Switch.events.LongPress,
      clusters.Switch.events.ShortRelease,
      clusters.Switch.events.MultiPressComplete,
    },
  },
  capability_handlers = {
  },
  supported_capabilities = {
    capabilities.temperatureMeasurement,
    capabilities.contactSensor,
    capabilities.motionSensor,
    capabilities.battery,
    capabilities.relativeHumidityMeasurement,
    capabilities.illuminanceMeasurement,
    capabilities.atmosphericPressureMeasurement,
    capabilities.waterSensor,
    capabilities.temperatureAlarm,
    capabilities.rainSensor,
    capabilities.hardwareFault
  },
  sub_drivers = {
    require("air-quality-sensor"),
    require("smoke-co-alarm")
  }
}

local matter_driver = MatterDriver("matter-sensor", matter_driver_template)
matter_driver:run()
