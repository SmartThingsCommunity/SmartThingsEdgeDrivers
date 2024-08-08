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

-- This can be removed once LuaLibs supports the PressureMeasurement cluster
if not pcall(function(cluster) return clusters[cluster] end,
             "PressureMeasurement") then
  clusters.PressureMeasurement = require "PressureMeasurement"
end

-- Include driver-side definitions when lua libs api version is < 10
local version = require "version"
if version.api < 10 then
  clusters.AirQuality = require "AirQuality"
  clusters.BooleanStateConfiguration = require "BooleanStateConfiguration"
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

-- local rainSensorID = "smilevirtual57983.customRainSensor"
-- local rainSensor = capabilities[rainSensorID]

local BATTERY_CHECKED = "__battery_checked"
local BOOLEAN_DEVICE_TYPES_CHECKED = "__boolean_device_types_checked"
local TEMP_BOUND_RECEIVED = "__temp_bound_received"
local TEMP_MIN = "__temp_min"
local TEMP_MAX = "__temp_max"

local HUE_MANUFACTURER_ID = 0x100B

local BOOLEAN_DEVICE_TYPE_INFO = {
  ["RAIN_SENSOR"] = { id = 0x0044, },
  ["WATER_FREEZE_DETECTOR"] = { id = 0x0043, },
  ["WATER_LEAK_DETECTOR"] = { id = 0x0041, },
  ["CONTACT_SENSOR"] = { id = 0x0015, },
}

local function set_device_type_per_endpoint(driver, device)
  for _, ep in ipairs(device.endpoints) do
      for _, dt in ipairs(ep.device_types) do
          for dt_name, info in pairs(BOOLEAN_DEVICE_TYPE_INFO) do
              if dt.device_type_id == info.id then
                  device:set_field(dt_name, ep.endpoint_id)
              end
          end
      end
  end
  device:set_field(BOOLEAN_DEVICE_TYPES_CHECKED, 1, {persist = true})
end

local function get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

local function set_field_for_endpoint(device, field, endpoint, value, additional_params)
  device:set_field(string.format("%s_%d", field, endpoint), value, additional_params)
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

local function check_for_battery(device)
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

  if supports_battery_percentage_remaining(device) then
    profile_name = profile_name .. "-battery"
  end

  if device:supports_capability(capabilities.rainSensor) then
    profile_name = profile_name .. "-rain"
  end

  if device:supports_capability(capabilities.temperatureAlert) then
    profile_name = profile_name .. "-freeze"
  end

  if device:supports_capability(capabilities.waterSensor) then
    profile_name = profile_name .. "-leak"
  end

  if device:supports_capability(capabilities.hardwareFault) then
    profile_name = profile_name .. "-fault"
  end

  -- remove leading "-"
  profile_name = string.sub(profile_name, 2)

  device:try_update_metadata({profile = profile_name})
  device:set_field(BATTERY_CHECKED, 1, {persist = true})
end

local function device_init(driver, device)
  log.info("device init")
  if not device:get_field(BATTERY_CHECKED) then
    check_for_battery(device)
  end
  if not device:get_field(BOOLEAN_DEVICE_TYPES_CHECKED) then
    set_device_type_per_endpoint(driver, device)
  end
  device:subscribe()
end

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    device:subscribe()
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
    -- Return if no data or RPC version < 4 (unit conversion for temperature
    -- range capability is only supported for RPC >= 4)
    if ib.data.value == nil or version.rpc < 4 then
      return
    end
    local temp = ib.data.value / 100.0
    local unit = "C"
    set_field_for_endpoint(device, TEMP_BOUND_RECEIVED..minOrMax, ib.endpoint_id, temp)
    local min = get_field_for_endpoint(device, TEMP_BOUND_RECEIVED..TEMP_MIN, ib.endpoint_id)
    local max = get_field_for_endpoint(device, TEMP_BOUND_RECEIVED..TEMP_MAX, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = min, maximum = max }, unit = unit }))
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
  local name = nil
  for dt_name, _ in pairs(BOOLEAN_DEVICE_TYPE_INFO) do
      local dt_ep_id = device:get_field(dt_name)
      if ib.endpoint_id == dt_ep_id then
          name = dt_name
          break
      end
  end
  if name == nil then
      log.error("No Boolean device type found on an endpoint, BooleanState handler aborted")
      return
  end
  device:emit_event_for_endpoint(ib.endpoint_id, BOOLEAN_CAP_EVENT_MAP[ib.data.value][name])
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

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed
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
    }
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
    capabilities.hardwareFault
  },
  sub_drivers = {
    require("air-quality-sensor"),
    require("smoke-co-alarm")
  }
}

local matter_driver = MatterDriver("matter-sensor", matter_driver_template)
matter_driver:run()
