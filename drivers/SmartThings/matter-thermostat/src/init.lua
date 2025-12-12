-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local log = require "log"
local version = require "version"
local MatterDriver = require "st.matter.driver"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"
local attribute_handlers = require "thermostat_handlers.attribute_handlers"
local capability_handlers = require "thermostat_handlers.capability_handlers"
local fields = require "thermostat_utils.fields"
local thermostat_utils = require "thermostat_utils.utils"
local embedded_cluster_utils = require "thermostat_utils.embedded_cluster_utils"

if version.api < 10 then
  clusters.HepaFilterMonitoring = require "embedded_clusters.HepaFilterMonitoring"
  clusters.ActivatedCarbonFilterMonitoring = require "embedded_clusters.ActivatedCarbonFilterMonitoring"
  clusters.AirQuality = require "embedded_clusters.AirQuality"
  clusters.CarbonMonoxideConcentrationMeasurement = require "embedded_clusters.CarbonMonoxideConcentrationMeasurement"
  clusters.CarbonDioxideConcentrationMeasurement = require "embedded_clusters.CarbonDioxideConcentrationMeasurement"
  clusters.FormaldehydeConcentrationMeasurement = require "embedded_clusters.FormaldehydeConcentrationMeasurement"
  clusters.NitrogenDioxideConcentrationMeasurement = require "embedded_clusters.NitrogenDioxideConcentrationMeasurement"
  clusters.OzoneConcentrationMeasurement = require "embedded_clusters.OzoneConcentrationMeasurement"
  clusters.Pm1ConcentrationMeasurement = require "embedded_clusters.Pm1ConcentrationMeasurement"
  clusters.Pm10ConcentrationMeasurement = require "embedded_clusters.Pm10ConcentrationMeasurement"
  clusters.Pm25ConcentrationMeasurement = require "embedded_clusters.Pm25ConcentrationMeasurement"
  clusters.RadonConcentrationMeasurement = require "embedded_clusters.RadonConcentrationMeasurement"
  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement = require "embedded_clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement"
end

if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded_clusters.ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "embedded_clusters.ElectricalPowerMeasurement"
end

if version.api < 13 then
  clusters.WaterHeaterMode = require "embedded_clusters.WaterHeaterMode"
end

local ThermostatLifecycleHandlers = {}

function ThermostatLifecycleHandlers.device_added(driver, device)
  local req = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  req:merge(clusters.Thermostat.attributes.ControlSequenceOfOperation:read(device))
  req:merge(clusters.FanControl.attributes.FanModeSequence:read(device))
  req:merge(clusters.FanControl.attributes.WindSupport:read(device))
  req:merge(clusters.FanControl.attributes.RockSupport:read(device))

  local thermostat_eps = device:get_endpoints(clusters.Thermostat.ID)
  if #thermostat_eps > 0 then
    req:merge(clusters.Thermostat.attributes.AttributeList:read(device))
  else
    device:set_field(fields.profiling_data.THERMOSTAT_RUNNING_STATE_SUPPORT, false)
  end
  local battery_feature_eps = device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
  if #battery_feature_eps > 0 then
    req:merge(clusters.PowerSource.attributes.AttributeList:read(device))
  else
    device:set_field(fields.profiling_data.BATTERY_SUPPORT, fields.battery_support.NO_BATTERY)
  end
  device:send(req)
  local heat_pump_eps = thermostat_utils.get_endpoints_by_device_type(device, fields.HEAT_PUMP_DEVICE_TYPE_ID) or {}
  if #heat_pump_eps > 0 then
    local thermostat_eps = thermostat_utils.get_endpoints_by_device_type(device, fields.THERMOSTAT_DEVICE_TYPE_ID) or {}
    local component_to_endpoint_map = {
      ["thermostatOne"] = thermostat_eps[1],
      ["thermostatTwo"] = thermostat_eps[2],
    }
    device:set_field(fields.COMPONENT_TO_ENDPOINT_MAP, component_to_endpoint_map, {persist = true})
  end
end

function ThermostatLifecycleHandlers.do_configure(driver, device)
  local device_cfg = require "thermostat_utils.device_configuration"
  device_cfg.match_profile(device)
end

function ThermostatLifecycleHandlers.driver_switched(driver, device)
  local device_cfg = require "thermostat_utils.device_configuration"
  device_cfg.match_profile(device)
end

function ThermostatLifecycleHandlers.device_init(driver, device)
  if device:get_field(fields.SUPPORTED_COMPONENT_CAPABILITIES) and (version.api < 15 or version.rpc < 9) then
    -- assume that device is using a modular profile on 0.57 FW, override supports_capability_by_id
    -- library function to utilize optional capabilities
    device:extend_device("supports_capability_by_id", thermostat_utils.supports_capability_by_id_modular)
  end
  device:subscribe()
  device:set_component_to_endpoint_fn(thermostat_utils.component_to_endpoint)
  device:set_endpoint_to_component_fn(thermostat_utils.endpoint_to_component)
  if not device:get_field(fields.setpoint_limit_device_field.MIN_SETPOINT_DEADBAND_CHECKED) then
    local auto_eps = device:get_endpoints(clusters.Thermostat.ID, {feature_bitmap = clusters.Thermostat.types.ThermostatFeature.AUTOMODE})
    --Query min setpoint deadband if needed
    if #auto_eps ~= 0 and device:get_field(fields.setpoint_limit_device_field.MIN_DEADBAND) == nil then
      device:send(clusters.Thermostat.attributes.MinSetpointDeadBand:read())
    end
  end

  -- device energy reporting must be handled cumulatively, periodically, or by both simulatanously.
  -- To ensure a single source of truth, we only handle a device's periodic reporting if cumulative reporting is not supported.
  local electrical_energy_measurement_eps = embedded_cluster_utils.get_endpoints(device, clusters.ElectricalEnergyMeasurement.ID)
  if #electrical_energy_measurement_eps > 0 then
    local cumulative_energy_eps = embedded_cluster_utils.get_endpoints(
      device,
      clusters.ElectricalEnergyMeasurement.ID,
      {feature_bitmap = clusters.ElectricalEnergyMeasurement.types.Feature.CUMULATIVE_ENERGY}
    )
    if #cumulative_energy_eps == 0 then device:set_field(fields.CUMULATIVE_REPORTS_NOT_SUPPORTED, true, {persist = false}) end
  end
end

function ThermostatLifecycleHandlers.info_changed(driver, device, event, args)
  if device:get_field(fields.SUPPORTED_COMPONENT_CAPABILITIES) then
    -- This indicates the device should be using a modular profile, so
    -- re-up subscription with new capabilities using the modular supports_capability override
    device:extend_device("supports_capability_by_id", thermostat_utils.supports_capability_by_id_modular)
  end

  if device.profile.id ~= args.old_st_store.profile.id then
    device:subscribe()
  end
end

function ThermostatLifecycleHandlers.device_removed(driver, device)
  device.log.info("device removed")
end

local matter_driver_template = {
  lifecycle_handlers = {
    added = ThermostatLifecycleHandlers.device_added,
    doConfigure = ThermostatLifecycleHandlers.do_configure,
    driverSwitched = ThermostatLifecycleHandlers.driver_switched,
    infoChanged = ThermostatLifecycleHandlers.info_changed,
    init = ThermostatLifecycleHandlers.device_init,
    removed = ThermostatLifecycleHandlers.device_removed,
  },
  matter_handlers = {
    attr = {
      [clusters.ActivatedCarbonFilterMonitoring.ID] = {
        [clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.ID] = attribute_handlers.activated_carbon_filter_change_indication_handler,
        [clusters.ActivatedCarbonFilterMonitoring.attributes.Condition.ID] = attribute_handlers.activated_carbon_filter_condition_handler,
      },
      [clusters.AirQuality.ID] = {
        [clusters.AirQuality.attributes.AirQuality.ID] = attribute_handlers.air_quality_handler,
      },
      [clusters.ElectricalEnergyMeasurement.ID] = {
        [clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported.ID] = attribute_handlers.energy_imported_factory(true),
        [clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported.ID] = attribute_handlers.energy_imported_factory(false),
      },
      [clusters.ElectricalPowerMeasurement.ID] = {
        [clusters.ElectricalPowerMeasurement.attributes.ActivePower.ID] = attribute_handlers.active_power_handler
      },
      [clusters.FanControl.ID] = {
        [clusters.FanControl.attributes.FanMode.ID] = attribute_handlers.fan_mode_handler,
        [clusters.FanControl.attributes.FanModeSequence.ID] = attribute_handlers.fan_mode_sequence_handler,
        [clusters.FanControl.attributes.PercentCurrent.ID] = attribute_handlers.percent_current_handler,
        [clusters.FanControl.attributes.RockSetting.ID] = attribute_handlers.rock_setting_handler,
        [clusters.FanControl.attributes.RockSupport.ID] = attribute_handlers.rock_support_handler,
        [clusters.FanControl.attributes.WindSetting.ID] = attribute_handlers.wind_setting_handler,
        [clusters.FanControl.attributes.WindSupport.ID] = attribute_handlers.wind_support_handler,
      },
      [clusters.HepaFilterMonitoring.ID] = {
        [clusters.HepaFilterMonitoring.attributes.ChangeIndication.ID] = attribute_handlers.hepa_filter_change_indication_handler,
        [clusters.HepaFilterMonitoring.attributes.Condition.ID] = attribute_handlers.hepa_filter_condition_handler,
      },
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = attribute_handlers.on_off_handler,
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.AttributeList.ID] = attribute_handlers.power_source_attribute_list_handler,
        [clusters.PowerSource.attributes.BatChargeLevel.ID] = attribute_handlers.bat_charge_level_handler,
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = attribute_handlers.bat_percent_remaining_handler,
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.relative_humidity_measured_value_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MaxMeasuredValue.ID] = attribute_handlers.temperature_measured_value_bounds_factory(fields.setpoint_limit_device_field.MAX_TEMP),
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.temperature_handler_factory(capabilities.temperatureMeasurement.temperature),
        [clusters.TemperatureMeasurement.attributes.MinMeasuredValue.ID] = attribute_handlers.temperature_measured_value_bounds_factory(fields.setpoint_limit_device_field.MIN_TEMP),
      },
      [clusters.Thermostat.ID] = {
        [clusters.Thermostat.attributes.AttributeList.ID] = attribute_handlers.thermostat_attribute_list_handler,
        [clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit.ID] = attribute_handlers.abs_cool_setpoint_limit_factory(fields.setpoint_limit_device_field.MAX_COOL),
        [clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit.ID] = attribute_handlers.abs_heat_setpoint_limit_factory(fields.setpoint_limit_device_field.MAX_HEAT),
        [clusters.Thermostat.attributes.AbsMinCoolSetpointLimit.ID] = attribute_handlers.abs_cool_setpoint_limit_factory(fields.setpoint_limit_device_field.MIN_COOL),
        [clusters.Thermostat.attributes.AbsMinHeatSetpointLimit.ID] = attribute_handlers.abs_heat_setpoint_limit_factory(fields.setpoint_limit_device_field.MIN_HEAT),
        [clusters.Thermostat.attributes.ControlSequenceOfOperation.ID] = attribute_handlers.control_sequence_of_operation_handler,
        [clusters.Thermostat.attributes.LocalTemperature.ID] = attribute_handlers.temperature_handler_factory(capabilities.temperatureMeasurement.temperature),
        [clusters.Thermostat.attributes.MinSetpointDeadBand.ID] = attribute_handlers.min_setpoint_deadband_handler,
        [clusters.Thermostat.attributes.OccupiedCoolingSetpoint.ID] = attribute_handlers.temperature_handler_factory(capabilities.thermostatCoolingSetpoint.coolingSetpoint),
        [clusters.Thermostat.attributes.OccupiedHeatingSetpoint.ID] = attribute_handlers.temperature_handler_factory(capabilities.thermostatHeatingSetpoint.heatingSetpoint),
        [clusters.Thermostat.attributes.SystemMode.ID] = attribute_handlers.system_mode_handler,
        [clusters.Thermostat.attributes.ThermostatRunningState.ID] = attribute_handlers.thermostat_running_state_handler,
      },
      [clusters.WaterHeaterMode.ID] = {
        [clusters.WaterHeaterMode.attributes.CurrentMode.ID] = attribute_handlers.water_heater_current_mode_handler,
        [clusters.WaterHeaterMode.attributes.SupportedModes.ID] = attribute_handlers.water_heater_supported_modes_handler
      },
      -- CONCENTRATION MEASUREMENT CLUSTERS --
      [clusters.CarbonDioxideConcentrationMeasurement.ID] = {
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.concentration_level_value_factory(capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern),
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.concentration_measured_value_factory(capabilities.carbonDioxideMeasurement.NAME, capabilities.carbonDioxideMeasurement.carbonDioxide, fields.units.PPM),
        [clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.concentration_measurement_unit_factory(capabilities.carbonDioxideMeasurement.NAME),
      },
      [clusters.CarbonMonoxideConcentrationMeasurement.ID] = {
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.concentration_level_value_factory(capabilities.carbonMonoxideHealthConcern.carbonMonoxideHealthConcern),
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.concentration_measured_value_factory(capabilities.carbonMonoxideMeasurement.NAME, capabilities.carbonMonoxideMeasurement.carbonMonoxideLevel, fields.units.PPM),
        [clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.concentration_measurement_unit_factory(capabilities.carbonMonoxideMeasurement.NAME),
      },
      [clusters.FormaldehydeConcentrationMeasurement.ID] = {
        [clusters.FormaldehydeConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.concentration_level_value_factory(capabilities.formaldehydeHealthConcern.formaldehydeHealthConcern),
        [clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.concentration_measured_value_factory(capabilities.formaldehydeMeasurement.NAME, capabilities.formaldehydeMeasurement.formaldehydeLevel, fields.units.PPM),
        [clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.concentration_measurement_unit_factory(capabilities.formaldehydeMeasurement.NAME),
      },
      [clusters.NitrogenDioxideConcentrationMeasurement.ID] = {
        [clusters.NitrogenDioxideConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.concentration_level_value_factory(capabilities.nitrogenDioxideHealthConcern.nitrogenDioxideHealthConcern),
        [clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.concentration_measured_value_factory(capabilities.nitrogenDioxideMeasurement.NAME, capabilities.nitrogenDioxideMeasurement.nitrogenDioxide, fields.units.PPM),
        [clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.concentration_measurement_unit_factory(capabilities.nitrogenDioxideMeasurement.NAME),
      },
      [clusters.OzoneConcentrationMeasurement.ID] = {
        [clusters.OzoneConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.concentration_level_value_factory(capabilities.ozoneHealthConcern.ozoneHealthConcern),
        [clusters.OzoneConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.concentration_measured_value_factory(capabilities.ozoneMeasurement.NAME, capabilities.ozoneMeasurement.ozone, fields.units.PPM),
        [clusters.OzoneConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.concentration_measurement_unit_factory(capabilities.ozoneMeasurement.NAME),
      },
      [clusters.Pm1ConcentrationMeasurement.ID] = {
        [clusters.Pm1ConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.concentration_level_value_factory(capabilities.veryFineDustHealthConcern.veryFineDustHealthConcern),
        [clusters.Pm1ConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.concentration_measured_value_factory(capabilities.veryFineDustSensor.NAME, capabilities.veryFineDustSensor.veryFineDustLevel, fields.units.UGM3),
        [clusters.Pm1ConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.concentration_measurement_unit_factory(capabilities.veryFineDustSensor.NAME),
      },
      [clusters.Pm10ConcentrationMeasurement.ID] = {
        [clusters.Pm10ConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.concentration_level_value_factory(capabilities.dustHealthConcern.dustHealthConcern),
        [clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.concentration_measured_value_factory(capabilities.dustSensor.NAME, capabilities.dustSensor.dustLevel, fields.units.UGM3),
        [clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.concentration_measurement_unit_factory(capabilities.dustSensor.NAME),
      },
      [clusters.Pm25ConcentrationMeasurement.ID] = {
        [clusters.Pm25ConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.concentration_level_value_factory(capabilities.fineDustHealthConcern.fineDustHealthConcern),
        [clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.concentration_measured_value_factory(capabilities.fineDustSensor.NAME, capabilities.fineDustSensor.fineDustLevel, fields.units.UGM3),
        [clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.concentration_measurement_unit_factory(capabilities.fineDustSensor.NAME),
      },
      [clusters.RadonConcentrationMeasurement.ID] = {
        [clusters.RadonConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.concentration_level_value_factory(capabilities.radonHealthConcern.radonHealthConcern),
        [clusters.RadonConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.concentration_measured_value_factory(capabilities.radonMeasurement.NAME, capabilities.radonMeasurement.radonLevel, fields.units.PCIL),
        [clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.concentration_measurement_unit_factory(capabilities.radonMeasurement.NAME),
      },
      [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID] = {
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue.ID] = attribute_handlers.concentration_level_value_factory(capabilities.tvocHealthConcern.tvocHealthConcern),
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.concentration_measured_value_factory(capabilities.tvocMeasurement.NAME, capabilities.tvocMeasurement.tvocLevel, fields.units.PPB),
        [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit.ID] = attribute_handlers.concentration_measurement_unit_factory(capabilities.tvocMeasurement.NAME),
      },
    },
  },
  capability_handlers = {
    [capabilities.airConditionerFanMode.ID] = {
      [capabilities.airConditionerFanMode.commands.setFanMode.NAME] = capability_handlers.fan_mode_command_factory(capabilities.airConditionerFanMode)
    },
    [capabilities.airPurifierFanMode.ID] = {
      [capabilities.airPurifierFanMode.commands.setAirPurifierFanMode.NAME] = capability_handlers.fan_mode_command_factory(capabilities.airPurifierFanMode)
    },
    [capabilities.fanMode.ID] = {
      [capabilities.fanMode.commands.setFanMode.NAME] = capability_handlers.fan_mode_command_factory(capabilities.fanMode)
    },
    [capabilities.fanOscillationMode.ID] = {
      [capabilities.fanOscillationMode.commands.setFanOscillationMode.NAME] = capability_handlers.handle_set_fan_oscillation_mode,
    },
    [capabilities.fanSpeedPercent.ID] = {
      [capabilities.fanSpeedPercent.commands.setPercent.NAME] = capability_handlers.handle_fan_speed_set_percent,
    },
    [capabilities.filterState.ID] = {
      [capabilities.filterState.commands.resetFilter.NAME] = capability_handlers.handle_filter_state_reset_filter,
    },
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = capability_handlers.handle_set_mode,
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.off.NAME] = capability_handlers.handle_switch_off,
      [capabilities.switch.commands.on.NAME] = capability_handlers.handle_switch_on,
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = capability_handlers.thermostat_set_setpoint_factory(clusters.Thermostat.attributes.OccupiedCoolingSetpoint)
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = capability_handlers.thermostat_set_setpoint_factory(clusters.Thermostat.attributes.OccupiedHeatingSetpoint)
    },
    [capabilities.thermostatFanMode.ID] = {
      [capabilities.thermostatFanMode.commands.fanAuto.NAME] = capability_handlers.thermostat_fan_mode_command_factory(capabilities.thermostatFanMode.thermostatFanMode.auto.NAME),
      [capabilities.thermostatFanMode.commands.fanOn.NAME] = capability_handlers.thermostat_fan_mode_command_factory(capabilities.thermostatFanMode.thermostatFanMode.on.NAME),
      [capabilities.thermostatFanMode.commands.setThermostatFanMode.NAME] = capability_handlers.fan_mode_command_factory(capabilities.thermostatFanMode),
    },
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.auto.NAME] = capability_handlers.thermostat_mode_command_factory(capabilities.thermostatMode.thermostatMode.auto.NAME),
      [capabilities.thermostatMode.commands.cool.NAME] = capability_handlers.thermostat_mode_command_factory(capabilities.thermostatMode.thermostatMode.cool.NAME),
      [capabilities.thermostatMode.commands.emergencyHeat.NAME] = capability_handlers.thermostat_mode_command_factory(capabilities.thermostatMode.thermostatMode.emergency_heat.NAME),
      [capabilities.thermostatMode.commands.heat.NAME] = capability_handlers.thermostat_mode_command_factory(capabilities.thermostatMode.thermostatMode.heat.NAME),
      [capabilities.thermostatMode.commands.off.NAME] = capability_handlers.thermostat_mode_command_factory(capabilities.thermostatMode.thermostatMode.off.NAME),
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = capability_handlers.handle_set_thermostat_mode,
    },
    [capabilities.windMode.ID] = {
      [capabilities.windMode.commands.setWindMode.NAME] = capability_handlers.handle_set_wind_mode,
    },
  },
  subscribed_attributes = {
    [capabilities.airConditionerFanMode.ID] = {
      clusters.FanControl.attributes.FanModeSequence,
      clusters.FanControl.attributes.FanMode
    },
    [capabilities.airPurifierFanMode.ID] = {
      clusters.FanControl.attributes.FanModeSequence,
      clusters.FanControl.attributes.FanMode
    },
    [capabilities.battery.ID] = {
      clusters.PowerSource.attributes.BatPercentRemaining
    },
    [capabilities.batteryLevel.ID] = {
      clusters.PowerSource.attributes.BatChargeLevel
    },
    [capabilities.energyMeter.ID] = {
      clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported,
      clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported
    },
    [capabilities.fanMode.ID] = {
      clusters.FanControl.attributes.FanModeSequence,
      clusters.FanControl.attributes.FanMode
    },
    [capabilities.fanOscillationMode.ID] = {
      clusters.FanControl.attributes.RockSupport,
      clusters.FanControl.attributes.RockSetting
    },
    [capabilities.fanSpeedPercent.ID] = {
      clusters.FanControl.attributes.PercentCurrent
    },
    [capabilities.filterState.ID] = {
      clusters.HepaFilterMonitoring.attributes.Condition,
      clusters.ActivatedCarbonFilterMonitoring.attributes.Condition
    },
    [capabilities.filterStatus.ID] = {
      clusters.HepaFilterMonitoring.attributes.ChangeIndication,
      clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication
    },
    [capabilities.mode.ID] = {
      clusters.WaterHeaterMode.attributes.CurrentMode,
      clusters.WaterHeaterMode.attributes.SupportedModes
    },
    [capabilities.powerConsumptionReport.ID] = {
      clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported,
      clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported
    },
    [capabilities.powerMeter.ID] = {
      clusters.ElectricalPowerMeasurement.attributes.ActivePower
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.switch.ID] = {
      clusters.OnOff.attributes.OnOff
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.Thermostat.attributes.LocalTemperature,
      clusters.TemperatureMeasurement.attributes.MeasuredValue,
      clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
      clusters.TemperatureMeasurement.attributes.MaxMeasuredValue
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
      clusters.Thermostat.attributes.AbsMinCoolSetpointLimit,
      clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit
    },
    [capabilities.thermostatFanMode.ID] = {
      clusters.FanControl.attributes.FanModeSequence,
      clusters.FanControl.attributes.FanMode
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
      clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
      clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit
    },
    [capabilities.thermostatMode.ID] = {
      clusters.Thermostat.attributes.SystemMode,
      clusters.Thermostat.attributes.ControlSequenceOfOperation
    },
    [capabilities.thermostatOperatingState.ID] = {
      clusters.Thermostat.attributes.ThermostatRunningState
    },
    [capabilities.windMode.ID] = {
      clusters.FanControl.attributes.WindSupport,
      clusters.FanControl.attributes.WindSetting
    },
    --  AIR QUALITY SENSOR DEVICE TYPE SPECIFIC CAPABILITIES --
    [capabilities.airQualityHealthConcern.ID] = {
      clusters.AirQuality.attributes.AirQuality
    },
    [capabilities.atmosphericPressureMeasurement.ID] = {
      clusters.PressureMeasurement.attributes.MeasuredValue
    },
    [capabilities.carbonDioxideHealthConcern.ID] = {
      clusters.CarbonDioxideConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.carbonDioxideMeasurement.ID] = {
      clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.CarbonDioxideConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.carbonMonoxideHealthConcern.ID] = {
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.carbonMonoxideMeasurement.ID] = {
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.CarbonMonoxideConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.dustHealthConcern.ID] = {
      clusters.Pm10ConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.dustSensor.ID] = {
      clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit,
      clusters.Pm10ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm10ConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.fineDustHealthConcern.ID] = {
      clusters.Pm25ConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.fineDustSensor.ID] = {
      clusters.Pm25ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm25ConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.formaldehydeHealthConcern.ID] = {
      clusters.FormaldehydeConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.formaldehydeMeasurement.ID] = {
      clusters.FormaldehydeConcentrationMeasurement.attributes.MeasuredValue,
      clusters.FormaldehydeConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.nitrogenDioxideHealthConcern.ID] = {
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.nitrogenDioxideMeasurement.ID] = {
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasuredValue,
      clusters.NitrogenDioxideConcentrationMeasurement.attributes.MeasurementUnit
    },
    [capabilities.ozoneHealthConcern.ID] = {
      clusters.OzoneConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.ozoneMeasurement.ID] = {
      clusters.OzoneConcentrationMeasurement.attributes.MeasuredValue,
      clusters.OzoneConcentrationMeasurement.attributes.MeasurementUnit
    },
    [capabilities.radonHealthConcern.ID] = {
      clusters.RadonConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.radonMeasurement.ID] = {
      clusters.RadonConcentrationMeasurement.attributes.MeasuredValue,
      clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.tvocHealthConcern.ID] = {
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue
    },
    [capabilities.tvocMeasurement.ID] = {
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue,
      clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit,
    },
    [capabilities.veryFineDustHealthConcern.ID] = {
      clusters.Pm1ConcentrationMeasurement.attributes.LevelValue,
    },
    [capabilities.veryFineDustSensor.ID] = {
      clusters.Pm1ConcentrationMeasurement.attributes.MeasuredValue,
      clusters.Pm1ConcentrationMeasurement.attributes.MeasurementUnit,
    },
  },
  supported_capabilities = {
    capabilities.airConditionerFanMode,
    capabilities.airQualityHealthConcern,
    capabilities.airPurifierFanMode,
    capabilities.battery,
    capabilities.batteryLevel,
    capabilities.carbonDioxideHealthConcern,
    capabilities.carbonDioxideMeasurement,
    capabilities.carbonMonoxideHealthConcern,
    capabilities.carbonMonoxideMeasurement,
    capabilities.dustHealthConcern,
    capabilities.dustSensor,
    capabilities.energyMeter,
    capabilities.fanMode,
    capabilities.fanOscillationMode,
    capabilities.fanSpeedPercent,
    capabilities.filterState,
    capabilities.filterStatus,
    capabilities.fineDustHealthConcern,
    capabilities.fineDustSensor,
    capabilities.formaldehydeHealthConcern,
    capabilities.formaldehydeMeasurement,
    capabilities.mode,
    capabilities.nitrogenDioxideHealthConcern,
    capabilities.nitrogenDioxideMeasurement,
    capabilities.ozoneHealthConcern,
    capabilities.ozoneMeasurement,
    capabilities.powerConsumptionReport,
    capabilities.powerMeter,
    capabilities.radonHealthConcern,
    capabilities.radonMeasurement,
    capabilities.thermostatCoolingSetpoint,
    capabilities.thermostatFanMode,
    capabilities.thermostatHeatingSetpoint,
    capabilities.thermostatMode,
    capabilities.thermostatOperatingState,
    capabilities.tvocHealthConcern,
    capabilities.tvocMeasurement,
    capabilities.veryFineDustHealthConcern,
    capabilities.veryFineDustSensor,
    capabilities.windMode,
  },
}

local matter_driver = MatterDriver("matter-thermostat", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
