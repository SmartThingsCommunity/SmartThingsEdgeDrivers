-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local version = require "version"
local embedded_cluster_utils = require "sensor_utils.embedded_cluster_utils"
local fields = require "sensor_utils.fields"
local match_static_profile = require "sub_drivers.smoke_co_alarm.static_configuration"

if version.api < 10 then
  clusters.CarbonMonoxideConcentrationMeasurement = require "embedded_clusters.CarbonMonoxideConcentrationMeasurement"
  clusters.SmokeCoAlarm = require "embedded_clusters.SmokeCoAlarm"
end

-- SUBDRIVER UTILS --

local smoke_co_alarm_utils = {}

local CARBON_MONOXIDE_MEASUREMENT_UNIT = "CarbonMonoxideConcentrationMeasurement_unit"

local HardwareFaultAlert = "__HardwareFaultAlert"
local BatteryAlert = "__BatteryAlert"
local BatteryLevel = "__BatteryLevel"

function smoke_co_alarm_utils.is_matter_smoke_co_alarm(opts, driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == fields.DEVICE_TYPE_ID.SMOKE_CO_ALARM then
        return true
      end
    end
  end

  return false
end


-- SMOKE CO ALARM LIFECYCLE HANDLERS --

local SmokeLifeycleHandlers = {}

function SmokeLifeycleHandlers.device_init(driver, device)
  device:subscribe()
end

function SmokeLifeycleHandlers.do_configure(driver, device)
  local battery_feature_eps = device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
  if #battery_feature_eps > 0 then
    device:send(clusters.PowerSource.attributes.AttributeList:read())
  else
    match_static_profile(device, fields.battery_support.NO_BATTERY)
  end
end

function SmokeLifeycleHandlers.info_changed(self, device, event, args)
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


-- CLUSTER ATTRIBUTE HANDLERS --

local sub_driver_handlers = {}

function sub_driver_handlers.smoke_co_alarm_state_factory(zeroEvent, nonZeroEvent)
  return function(driver, device, ib, response)
    if ib.data.value == 0 and zeroEvent ~= nil then
      device:emit_event_for_endpoint(ib.endpoint_id, zeroEvent)
    elseif nonZeroEvent ~= nil then
      device:emit_event_for_endpoint(ib.endpoint_id, nonZeroEvent)
    end
  end
end

function sub_driver_handlers.test_in_progress_handler(driver, device, ib, response)
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

function sub_driver_handlers.carbon_monoxide_measured_value_handler(driver, device, ib, response)
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

function sub_driver_handlers.carbon_monoxide_measurement_unit_handler(driver, device, ib, response)
  local unit = ib.data.value
  device:set_field(CARBON_MONOXIDE_MEASUREMENT_UNIT, unit, { persist = true })
end

function sub_driver_handlers.hardware_fault_capability_handler(device)
  local batLevel, batAlert  = device:get_field(BatteryLevel), device:get_field(BatteryAlert)
  if device:get_field(HardwareFaultAlert) == true or (batLevel and batAlert and (batAlert > batLevel)) then
    device:emit_event(capabilities.hardwareFault.hardwareFault.detected())
  else
    device:emit_event(capabilities.hardwareFault.hardwareFault.clear())
  end
end

function sub_driver_handlers.hardware_fault_alert_handler(driver, device, ib, response)
  device:set_field(HardwareFaultAlert, ib.data.value, {persist = true})
  sub_driver_handlers.hardware_fault_capability_handler(device)
end

function sub_driver_handlers.battery_alert_handler(driver, device, ib, response)
  device:set_field(BatteryAlert, ib.data.value, {persist = true})
  sub_driver_handlers.hardware_fault_capability_handler(device)
end

function sub_driver_handlers.power_source_attribute_list_handler(driver, device, ib, response)
  for _, attr in ipairs(ib.data.elements) do
    -- Re-profile the device if BatPercentRemaining (Attribute ID 0x0C) or
    -- BatChargeLevel (Attribute ID 0x0E) is present.
    if attr.value == 0x0C then
      smoke_co_alarm_utils.match_profile(device, fields.battery_support.BATTERY_PERCENTAGE)
      return
    elseif attr.value == 0x0E then
      smoke_co_alarm_utils.match_profile(device, fields.battery_support.BATTERY_LEVEL)
      return
    end
  end
end

function sub_driver_handlers.bat_charge_level_handler(driver, device, ib, response)
  device:set_field(BatteryLevel, ib.data.value, {persist = true}) -- value used in hardware_fault_capability_handler
  if device:supports_capability(capabilities.batteryLevel) then -- check required since attribute is subscribed to even without batteryLevel support, to set the field above
    if ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.OK then
      device:emit_event(capabilities.batteryLevel.battery.normal())
    elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.WARNING then
      device:emit_event(capabilities.batteryLevel.battery.warning())
    elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.CRITICAL then
      device:emit_event(capabilities.batteryLevel.battery.critical())
    end
  end
end


-- SUBDRIVER TEMPLATE --

local matter_smoke_co_alarm_handler = {
  NAME = "matter-smoke-co-alarm",
  lifecycle_handlers = {
    init = SmokeLifeycleHandlers.device_init,
    infoChanged = SmokeLifeycleHandlers.info_changed,
    doConfigure = SmokeLifeycleHandlers.do_configure
  },
  matter_handlers = {
    attr = {
      [clusters.CarbonMonoxideConcentrationMeasurement.ID] = {
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue.ID] = sub_driver_handlers.carbon_monoxide_measured_value_handler,
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = sub_driver_handlers.carbon_monoxide_measurement_unit_handler,
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.AttributeList.ID] = sub_driver_handlers.power_source_attribute_list_handler,
        [clusters.PowerSource.attributes.BatChargeLevel.ID] = sub_driver_handlers.bat_charge_level_handler,
      },
      [clusters.SmokeCoAlarm.ID] = {
        [clusters.SmokeCoAlarm.attributes.BatteryAlert.ID] = sub_driver_handlers.battery_alert_handler,
        [clusters.SmokeCoAlarm.attributes.COState.ID] = sub_driver_handlers.smoke_co_alarm_state_factory(capabilities.carbonMonoxideDetector.carbonMonoxide.clear(), capabilities.carbonMonoxideDetector.carbonMonoxide.detected()),
        [clusters.SmokeCoAlarm.attributes.HardwareFaultAlert.ID] = sub_driver_handlers.hardware_fault_alert_handler,
        [clusters.SmokeCoAlarm.attributes.SmokeState.ID] = sub_driver_handlers.smoke_co_alarm_state_factory(capabilities.smokeDetector.smoke.clear(), capabilities.smokeDetector.smoke.detected()),
        [clusters.SmokeCoAlarm.attributes.TestInProgress.ID] = sub_driver_handlers.test_in_progress_handler,
      },
    },
  },
  can_handle = smoke_co_alarm_utils.is_matter_smoke_co_alarm
}

return matter_smoke_co_alarm_handler