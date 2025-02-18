-- Copyright 2024 SmartThings
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
local embedded_cluster_utils = require "embedded-cluster-utils"

local CARBON_MONOXIDE_MEASUREMENT_UNIT = "CarbonMonoxideConcentrationMeasurement_unit"
local SMOKE_CO_ALARM_DEVICE_TYPE_ID = 0x0076
local PROFILE_MATCHED = "__profile_matched"

local version = require "version"
if version.api < 10 then
  clusters.SmokeCoAlarm = require "SmokeCoAlarm"
end

local function is_matter_smoke_co_alarm(opts, driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == SMOKE_CO_ALARM_DEVICE_TYPE_ID then
        return true
      end
    end
  end

  return false
end

local tbl_contains = function(t, val)
  for _, v in pairs(t) do
    if v == val then
      return true
    end
  end
  return false
end

local supported_profiles =
{
  "co",
  "co-comeas",
  "smoke",
  "smoke-co-comeas",
  "smoke-co-temp-humidity-comeas"
}

local function match_profile(device)
  local smoke_eps = embedded_cluster_utils.get_endpoints(device, clusters.SmokeCoAlarm.ID, {feature_bitmap = clusters.SmokeCoAlarm.types.Feature.SMOKE_ALARM})
  local co_eps = embedded_cluster_utils.get_endpoints(device, clusters.SmokeCoAlarm.ID, {feature_bitmap = clusters.SmokeCoAlarm.types.Feature.CO_ALARM})
  local temp_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureMeasurement.ID)
  local humidity_eps = embedded_cluster_utils.get_endpoints(device, clusters.RelativeHumidityMeasurement.ID)
  local co_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.CarbonMonoxideConcentrationMeasurement.ID, {feature_bitmap = clusters.CarbonMonoxideConcentrationMeasurement.types.Feature.NUMERIC_MEASUREMENT})
  local co_level_eps = embedded_cluster_utils.get_endpoints(device, clusters.CarbonMonoxideConcentrationMeasurement.ID, {feature_bitmap = clusters.CarbonMonoxideConcentrationMeasurement.types.Feature.LEVEL_INDICATION})

  local profile_name = ""

  -- battery and hardware fault are mandatory
  if #smoke_eps > 0 then
    profile_name = profile_name .. "-smoke"
  end
  if #co_eps > 0 then
    profile_name = profile_name .. "-co"
  end
  if #temp_eps > 0 then
    profile_name = profile_name .. "-temp"
  end
  if #humidity_eps > 0 then
    profile_name = profile_name .. "-humidity"
  end
  if #co_meas_eps > 0 then
    profile_name = profile_name .. "-comeas"
  end
  if #co_level_eps > 0 then
    profile_name = profile_name .. "-colevel"
  end

  -- remove leading "-"
  profile_name = string.sub(profile_name, 2)

  if tbl_contains(supported_profiles, profile_name) then
    device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
  else
    device.log.warn_with({hub_logs=true}, string.format("No matching profile for device. Tried to use profile %s.", profile_name))
    profile_name = ""
    if #smoke_eps > 0 and #co_eps > 0 then
      profile_name = "smoke-co"
    elseif #smoke_eps > 0 and #co_eps == 0 then
      profile_name = "smoke"
    elseif #co_eps > 0 and #smoke_eps == 0 then
      profile_name = "co"
    end
    device.log.info_with({hub_logs=true}, string.format("Using generic device profile %s.", profile_name))
  end
  device:try_update_metadata({profile = profile_name})
  device:set_field(PROFILE_MATCHED, 1 , {persist = true})
end

local function device_init(driver, device)
  if not device:get_field(PROFILE_MATCHED) then
    match_profile(device)
  end
  device:subscribe()
end

local function info_changed(self, device, event, args)
  if device.preferences then
    if device.preferences["certifiedpreferences.smokeSensorSensitivity"] ~= args.old_st_store.preferences["certifiedpreferences.smokeSensorSensitivity"] then
      local eps = embedded_cluster_utils.get_endpoints(device, clusters.SmokeCoAlarm.ID)
      if #eps > 0 then
        local smokeSensorSensitivity = device.preferences["certifiedpreferences.smokeSensorSensitivity"]
        if smokeSensorSensitivity == "0" then -- High
          device:send(clusters.SmokeCoAlarm.attributes.SmokeSensitivityLevel:write(device, eps[1], clusters.SmokeCoAlarm.types.SensitivityEnum.HIGH))
        elseif smokeSensorSensitivity == "1" then -- Medium
          device:send(clusters.SmokeCoAlarm.attributes.SmokeSensitivityLevel:write(device, eps[1], clusters.SmokeCoAlarm.types.SensitivityEnum.STANDARD))
        elseif smokeSensorSensitivity == "2" then -- Low
          device:send(clusters.SmokeCoAlarm.attributes.SmokeSensitivityLevel:write(device, eps[1], clusters.SmokeCoAlarm.types.SensitivityEnum.LOW))
        end
      end
    end
  end

  -- resubscribe to new attributes as needed if a profile switch occured
  if device.profile.id ~= args.old_st_store.profile.id then
    device:subscribe()
  end
end

-- Matter Handlers --
local function binary_state_handler_factory(zeroEvent, nonZeroEvent)
  return function(driver, device, ib, response)
    if ib.data.value == 0 and zeroEvent ~= nil then
      device:emit_event_for_endpoint(ib.endpoint_id, zeroEvent)
    elseif nonZeroEvent ~= nil then
      device:emit_event_for_endpoint(ib.endpoint_id, nonZeroEvent)
    end
  end
end

local function bool_handler_factory(trueEvent, falseEvent)
  return function(driver, device, ib, response)
    if ib.data.value and trueEvent ~= nil then
      device:emit_event_for_endpoint(ib.endpoint_id, trueEvent)
    elseif falseEvent ~= nil then
      device:emit_event_for_endpoint(ib.endpoint_id, falseEvent)
    end
  end
end

local function test_in_progress_event_handler(driver, device, ib, response)
  if device:supports_capability(capabilities.smokeDetector) then
    if ib.data.value then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smokeDetector.smoke.tested())
    else
      device:send(clusters.SmokeCoAlarm.attributes.SmokeState:read(device))
    end
  end
  if device:supports_capability(capabilities.carbonMonoxideDetector) then
    if ib.data.value then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.carbonMonoxideDetector.carbonMonoxide.tested())
    else
      device:send(clusters.SmokeCoAlarm.attributes.COState:read(device))
    end
  end
end

local function carbon_monoxide_attr_handler(driver, device, ib, response)
  local value = ib.data.value
  local unit = device:get_field(CARBON_MONOXIDE_MEASUREMENT_UNIT)
  if unit == clusters.CarbonMonoxideConcentrationMeasurement.types.MeasurementUnitEnum.PPB then
    value = value / 1000
  elseif unit == clusters.CarbonMonoxideConcentrationMeasurement.types.MeasurementUnitEnum.PPT then
    value = value / 1000000
  end
  value = math.floor(value)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.carbonMonoxideMeasurement.carbonMonoxideLevel({value = value, unit = "ppm"}))
end

local function carbon_monoxide_unit_attr_handler(driver, device, ib, response)
  local unit = ib.data.value
  device:set_field(CARBON_MONOXIDE_MEASUREMENT_UNIT, unit, { persist = true })
end

local function battery_alert_attr_handler(driver, device, ib, response)
  if ib.data.value == clusters.SmokeCoAlarm.types.AlarmStateEnum.NORMAL then
    device:emit_event(capabilities.batteryLevel.battery.normal())
  elseif ib.data.value == clusters.SmokeCoAlarm.types.AlarmStateEnum.WARNING then
    device:emit_event(capabilities.batteryLevel.battery.warning())
  elseif ib.data.value == clusters.SmokeCoAlarm.types.AlarmStateEnum.CRITICAL then
    device:emit_event(capabilities.batteryLevel.battery.critical())
  end
end

local matter_smoke_co_alarm_handler = {
  NAME = "matter-smoke-co-alarm",
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed
  },
  matter_handlers = {
    attr = {
      [clusters.SmokeCoAlarm.ID] = {
        [clusters.SmokeCoAlarm.attributes.SmokeState.ID] = binary_state_handler_factory(capabilities.smokeDetector.smoke.clear(), capabilities.smokeDetector.smoke.detected()),
        [clusters.SmokeCoAlarm.attributes.COState.ID] = binary_state_handler_factory(capabilities.carbonMonoxideDetector.carbonMonoxide.clear(), capabilities.carbonMonoxideDetector.carbonMonoxide.detected()),
        [clusters.SmokeCoAlarm.attributes.BatteryAlert.ID] = battery_alert_attr_handler,
        [clusters.SmokeCoAlarm.attributes.TestInProgress.ID] = test_in_progress_event_handler,
        [clusters.SmokeCoAlarm.attributes.HardwareFaultAlert.ID] = bool_handler_factory(capabilities.hardwareFault.hardwareFault.detected(), capabilities.hardwareFault.hardwareFault.clear()),
      },
      [clusters.CarbonMonoxideConcentrationMeasurement.ID] = {
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue.ID] = carbon_monoxide_attr_handler,
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = carbon_monoxide_unit_attr_handler,
      }
    },
  },
  subscribed_attributes = {
    [capabilities.smokeDetector.ID] = {
      clusters.SmokeCoAlarm.attributes.SmokeState,
      clusters.SmokeCoAlarm.attributes.TestInProgress,
    },
    [capabilities.carbonMonoxideDetector.ID] = {
      clusters.SmokeCoAlarm.attributes.COState,
      clusters.SmokeCoAlarm.attributes.TestInProgress,
    },
    [capabilities.hardwareFault.ID] = {
      clusters.SmokeCoAlarm.attributes.HardwareFaultAlert
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.TemperatureMeasurement.attributes.MeasuredValue
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.carbonMonoxideMeasurement.ID] = {
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.batteryLevel.ID] = {
      clusters.SmokeCoAlarm.attributes.BatteryAlert,
    }
  },
  can_handle = is_matter_smoke_co_alarm
}

return matter_smoke_co_alarm_handler