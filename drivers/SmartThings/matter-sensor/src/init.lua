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

local battery_support = {
  NO_BATTERY = "NO_BATTERY",
  BATTERY_LEVEL = "BATTERY_LEVEL",
  BATTERY_PERCENTAGE = "BATTERY_PERCENTAGE"
}

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
                  device:set_field(dt_name, ep.endpoint_id, { persist = true })
                  device:send(clusters.BooleanStateConfiguration.attributes.SupportedSensitivityLevels:read(device, ep.endpoint_id))
              end
          end
      end
  end
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

local function match_profile(driver, device, battery_supported)
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

  if battery_supported == battery_support.BATTERY_PERCENTAGE then
    profile_name = profile_name .. "-battery"
  elseif battery_supported == battery_support.BATTERY_LEVEL then
    profile_name = profile_name .. "-batteryLevel"
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

local function do_configure(driver, device)
  local battery_feature_eps = device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
  -- Hue devices support the PowerSource cluster but don't support reporting battery percentage remaining
  if #battery_feature_eps > 0 and device.manufacturer_info.vendor_id ~= HUE_MANUFACTURER_ID then
    local attribute_list_read = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
    attribute_list_read:merge(clusters.PowerSource.attributes.AttributeList:read())
    device:send(attribute_list_read)
  else
    match_profile(driver, device, battery_support.NO_BATTERY)
  end
end

local function device_init(driver, device)
  log.info("device init")
  set_boolean_device_type_per_endpoint(driver, device)
  device:subscribe()
end

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    set_boolean_device_type_per_endpoint(driver, device)
    device:subscribe()
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
      device:set_field(info.sensitivity_max, ib.data.value, {persist = true})
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

local function battery_charge_level_attr_handler(driver, device, ib, response)
  if ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.OK then
    device:emit_event(capabilities.batteryLevel.battery.normal())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.WARNING then
    device:emit_event(capabilities.batteryLevel.battery.warning())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.CRITICAL then
    device:emit_event(capabilities.batteryLevel.battery.critical())
  end
end

local function power_source_attribute_list_handler(driver, device, ib, response)
  for _, attr in ipairs(ib.data.elements) do
    -- Re-profile the device if BatPercentRemaining (Attribute ID 0x0C) or
    -- BatChargeLevel (Attribute ID 0x0E) is present.
    if attr.value == 0x0C then
      match_profile(driver, device, battery_support.BATTERY_PERCENTAGE)
      return
    elseif attr.value == 0x0E then
      match_profile(driver, device, battery_support.BATTERY_LEVEL)
      return
    end
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

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed,
    doConfigure = do_configure,
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
        [clusters.PowerSource.attributes.AttributeList.ID] = power_source_attribute_list_handler,
        [clusters.PowerSource.attributes.BatChargeLevel.ID] = battery_charge_level_attr_handler,
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
    }
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
    [capabilities.batteryLevel.ID] = {
      clusters.PowerSource.attributes.BatChargeLevel,
      clusters.SmokeCoAlarm.attributes.BatteryAlert,
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
  capability_handlers = {
  },
  supported_capabilities = {
    capabilities.temperatureMeasurement,
    capabilities.contactSensor,
    capabilities.motionSensor,
    capabilities.battery,
    capabilities.batteryLevel,
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
