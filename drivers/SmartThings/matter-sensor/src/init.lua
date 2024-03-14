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

local BATTERY_CHECKED = "__battery_checked"

local HUE_MANUFACTURER_ID = 0x100B

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

local function humidity_attr_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local humidity = utils.round(measured_value / 100.0)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(humidity))
  end
end

local function boolean_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.contactSensor.contact.closed())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.contactSensor.contact.open())
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
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temperature_attr_handler
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
    }
  },
  -- TODO Once capabilities all have default handlers move this info there, and
  -- use `supported_capabilities`
  subscribed_attributes = {
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.TemperatureMeasurement.attributes.MeasuredValue
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
  },
}

local matter_driver = MatterDriver("matter-sensor", matter_driver_template)
matter_driver:run()
