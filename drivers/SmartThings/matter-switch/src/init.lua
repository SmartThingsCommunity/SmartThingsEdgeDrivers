-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local MatterDriver = require "st.matter.driver"
local capabilities = require "st.capabilities"
local device_lib = require "st.device"
local clusters = require "st.matter.clusters"
local log = require "log"
local version = require "version"
local cfg = require "switch_utils.device_configuration"
local device_cfg = cfg.DeviceCfg
local switch_cfg = cfg.SwitchCfg
local button_cfg = cfg.ButtonCfg
local fields = require "switch_utils.fields"
local switch_utils = require "switch_utils.utils"
local attribute_handlers = require "switch_handlers.attribute_handlers"
local event_handlers = require "switch_handlers.event_handlers"
local capability_handlers = require "switch_handlers.capability_handlers"
local embedded_cluster_utils = require "switch_utils.embedded_cluster_utils"

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded_clusters.ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "embedded_clusters.ElectricalPowerMeasurement"
  clusters.PowerTopology = require "embedded_clusters.PowerTopology"
  clusters.ValveConfigurationAndControl = require "embedded_clusters.ValveConfigurationAndControl"
end

if version.api < 16 then
  clusters.Descriptor = require "embedded_clusters.Descriptor"
end

local SwitchLifecycleHandlers = {}

function SwitchLifecycleHandlers.device_added(driver, device)
  -- refresh child devices to get an initial attribute state for OnOff in case child device
  -- was created after the initial subscription report
  if device.network_type == device_lib.NETWORK_TYPE_CHILD then
    device:send(clusters.OnOff.attributes.OnOff:read(device))
  elseif device.network_type == device_lib.NETWORK_TYPE_MATTER then
    switch_utils.handle_electrical_sensor_info(device)
  end

  -- call device init in case init is not called after added due to device caching
  SwitchLifecycleHandlers.device_init(driver, device)
end

function SwitchLifecycleHandlers.do_configure(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and not switch_utils.detect_bridge(device) then
    switch_cfg.set_device_control_options(device)
    device_cfg.match_profile(driver, device)
  end
end

function SwitchLifecycleHandlers.driver_switched(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and not switch_utils.detect_bridge(device) then
    device_cfg.match_profile(driver, device)
  end
end

function SwitchLifecycleHandlers.info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    if device.network_type == device_lib.NETWORK_TYPE_MATTER then
      device:subscribe()
      button_cfg.configure_buttons(device,
        device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
      )
    elseif device.network_type == device_lib.NETWORK_TYPE_CHILD then
      switch_utils.update_subscriptions(device:get_parent_device()) -- parent device required to scan through EPs and update subscriptions
    end
  end

  if device.network_type == device_lib.NETWORK_TYPE_MATTER and not switch_utils.detect_bridge(device) then
    if device.matter_version.software ~= args.old_st_store.matter_version.software then
      device_cfg.match_profile(driver, device)
    end
  end
end

function SwitchLifecycleHandlers.device_init(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then
    switch_utils.check_field_name_updates(device)
    device:set_component_to_endpoint_fn(switch_utils.component_to_endpoint)
    device:set_endpoint_to_component_fn(switch_utils.endpoint_to_component)
    if device:get_field(fields.IS_PARENT_CHILD_DEVICE) then
      device:set_find_child(switch_utils.find_child)
    end
    switch_utils.update_subscriptions(device)

    -- device energy reporting must be handled cumulatively, periodically, or by both simulatanously.
    -- To ensure a single source of truth, we only handle a device's periodic reporting if cumulative reporting is not supported.
    if #embedded_cluster_utils.get_endpoints(device, clusters.ElectricalEnergyMeasurement.ID,
      {feature_bitmap = clusters.ElectricalEnergyMeasurement.types.Feature.CUMULATIVE_ENERGY}) > 0 then
        device:set_field(fields.CUMULATIVE_REPORTS_SUPPORTED, true, {persist = false})
    end
  end
end

function SwitchLifecycleHandlers.device_removed(driver, device)
  device.log.info("device removed")
end

local matter_driver_template = {
  lifecycle_handlers = {
    added = SwitchLifecycleHandlers.device_added,
    doConfigure = SwitchLifecycleHandlers.do_configure,
    driverSwitched = SwitchLifecycleHandlers.driver_switched,
    infoChanged = SwitchLifecycleHandlers.info_changed,
    init = SwitchLifecycleHandlers.device_init,
    removed = SwitchLifecycleHandlers.device_removed,
  },
  matter_handlers = {
    attr = {
      [clusters.ColorControl.ID] = {
        [clusters.ColorControl.attributes.ColorCapabilities.ID] = attribute_handlers.color_capabilities_handler,
        [clusters.ColorControl.attributes.ColorMode.ID] = attribute_handlers.color_mode_handler,
        [clusters.ColorControl.attributes.ColorTemperatureMireds.ID] = attribute_handlers.color_temperature_mireds_handler,
        [clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds.ID] = attribute_handlers.color_temp_physical_mireds_bounds_factory(fields.COLOR_TEMP_MIN), -- max mireds = min kelvin
        [clusters.ColorControl.attributes.ColorTempPhysicalMinMireds.ID] = attribute_handlers.color_temp_physical_mireds_bounds_factory(fields.COLOR_TEMP_MAX), -- min mireds = max kelvin
        [clusters.ColorControl.attributes.CurrentHue.ID] = attribute_handlers.current_hue_handler,
        [clusters.ColorControl.attributes.CurrentSaturation.ID] = attribute_handlers.current_saturation_handler,
        [clusters.ColorControl.attributes.CurrentX.ID] = attribute_handlers.current_x_handler,
        [clusters.ColorControl.attributes.CurrentY.ID] = attribute_handlers.current_y_handler,
      },
      [clusters.Descriptor.ID] = {
        [clusters.Descriptor.attributes.PartsList.ID] = attribute_handlers.parts_list_handler,
      },
      [clusters.ElectricalEnergyMeasurement.ID] = {
        [clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported.ID] = attribute_handlers.energy_imported_factory(false),
        [clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported.ID] = attribute_handlers.energy_imported_factory(true),
      },
      [clusters.ElectricalPowerMeasurement.ID] = {
        [clusters.ElectricalPowerMeasurement.attributes.ActivePower.ID] = attribute_handlers.active_power_handler,
      },
      [clusters.FanControl.ID] = {
        [clusters.FanControl.attributes.FanMode.ID] = attribute_handlers.fan_mode_handler,
        [clusters.FanControl.attributes.FanModeSequence.ID] = attribute_handlers.fan_mode_sequence_handler,
        [clusters.FanControl.attributes.PercentCurrent.ID] = attribute_handlers.percent_current_handler
      },
      [clusters.IlluminanceMeasurement.ID] = {
        [clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.illuminance_measured_value_handler
      },
      [clusters.LevelControl.ID] = {
        [clusters.LevelControl.attributes.CurrentLevel.ID] = attribute_handlers.level_control_current_level_handler,
        [clusters.LevelControl.attributes.MaxLevel.ID] = attribute_handlers.level_bounds_handler_factory(fields.LEVEL_MAX),
        [clusters.LevelControl.attributes.MinLevel.ID] = attribute_handlers.level_bounds_handler_factory(fields.LEVEL_MIN),
      },
      [clusters.OccupancySensing.ID] = {
        [clusters.OccupancySensing.attributes.Occupancy.ID] = attribute_handlers.occupancy_handler,
      },
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = attribute_handlers.on_off_attr_handler,
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.AttributeList.ID] = attribute_handlers.power_source_attribute_list_handler,
        [clusters.PowerSource.attributes.BatChargeLevel.ID] = attribute_handlers.bat_charge_level_handler,
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = attribute_handlers.bat_percent_remaining_handler,
      },
      [clusters.PowerTopology.ID] = {
        [clusters.PowerTopology.attributes.AvailableEndpoints.ID] = attribute_handlers.available_endpoints_handler,
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.relative_humidity_measured_value_handler
      },
      [clusters.Switch.ID] = {
        [clusters.Switch.attributes.MultiPressMax.ID] = attribute_handlers.multi_press_max_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MaxMeasuredValue.ID] = attribute_handlers.temperature_measured_value_bounds_factory(fields.TEMP_MAX),
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = attribute_handlers.temperature_measured_value_handler,
        [clusters.TemperatureMeasurement.attributes.MinMeasuredValue.ID] = attribute_handlers.temperature_measured_value_bounds_factory(fields.TEMP_MIN),
      },
      [clusters.ValveConfigurationAndControl.ID] = {
        [clusters.ValveConfigurationAndControl.attributes.CurrentLevel.ID] = attribute_handlers.valve_configuration_current_level_handler,
        [clusters.ValveConfigurationAndControl.attributes.CurrentState.ID] = attribute_handlers.valve_configuration_current_state_handler,
      },
    },
    event = {
      [clusters.Switch.ID] = {
        [clusters.Switch.events.InitialPress.ID] = event_handlers.initial_press_handler,
        [clusters.Switch.events.LongPress.ID] = event_handlers.long_press_handler,
        [clusters.Switch.events.MultiPressComplete.ID] = event_handlers.multi_press_complete_handler,
        [clusters.Switch.events.ShortRelease.ID] = event_handlers.short_release_handler,
      }
    },
    fallback = switch_utils.matter_handler,
  },
  subscribed_attributes = {
    [capabilities.battery.ID] = {
      clusters.PowerSource.attributes.BatPercentRemaining,
    },
    [capabilities.batteryLevel.ID] = {
      clusters.PowerSource.attributes.BatChargeLevel,
    },
    [capabilities.colorControl.ID] = {
      clusters.ColorControl.attributes.ColorMode,
      clusters.ColorControl.attributes.CurrentHue,
      clusters.ColorControl.attributes.CurrentSaturation,
      clusters.ColorControl.attributes.CurrentX,
      clusters.ColorControl.attributes.CurrentY,
    },
    [capabilities.colorTemperature.ID] = {
      clusters.ColorControl.attributes.ColorTemperatureMireds,
      clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
      clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
    },
    [capabilities.energyMeter.ID] = {
      clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
      clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported
    },
    [capabilities.fanMode.ID] = {
      clusters.FanControl.attributes.FanModeSequence,
      clusters.FanControl.attributes.FanMode
    },
    [capabilities.fanSpeedPercent.ID] = {
      clusters.FanControl.attributes.PercentCurrent
    },
    [capabilities.illuminanceMeasurement.ID] = {
      clusters.IlluminanceMeasurement.attributes.MeasuredValue
    },
    [capabilities.motionSensor.ID] = {
      clusters.OccupancySensing.attributes.Occupancy
    },
    [capabilities.level.ID] = {
      clusters.ValveConfigurationAndControl.attributes.CurrentLevel
    },
    [capabilities.switch.ID] = {
      clusters.OnOff.attributes.OnOff
    },
    [capabilities.powerMeter.ID] = {
      clusters.ElectricalPowerMeasurement.attributes.ActivePower
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.switchLevel.ID] = {
      clusters.LevelControl.attributes.CurrentLevel,
      clusters.LevelControl.attributes.MaxLevel,
      clusters.LevelControl.attributes.MinLevel,
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.TemperatureMeasurement.attributes.MeasuredValue,
      clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
      clusters.TemperatureMeasurement.attributes.MaxMeasuredValue
    },
    [capabilities.valve.ID] = {
      clusters.ValveConfigurationAndControl.attributes.CurrentState
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
    [capabilities.colorControl.ID] = {
      [capabilities.colorControl.commands.setColor.NAME] = capability_handlers.handle_set_color,
      [capabilities.colorControl.commands.setHue.NAME] = capability_handlers.handle_set_hue,
      [capabilities.colorControl.commands.setSaturation.NAME] = capability_handlers.handle_set_saturation,
    },
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = capability_handlers.handle_set_color_temperature,
    },
    [capabilities.fanMode.ID] = {
      [capabilities.fanMode.commands.setFanMode.NAME] = capability_handlers.handle_set_fan_mode
    },
    [capabilities.fanSpeedPercent.ID] = {
      [capabilities.fanSpeedPercent.commands.setPercent.NAME] = capability_handlers.handle_fan_speed_set_percent
    },
    [capabilities.level.ID] = {
      [capabilities.level.commands.setLevel.NAME] = capability_handlers.handle_set_level
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.off.NAME] = capability_handlers.handle_switch_off,
      [capabilities.switch.commands.on.NAME] = capability_handlers.handle_switch_on,
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = capability_handlers.handle_switch_set_level
    },
    [capabilities.valve.ID] = {
      [capabilities.valve.commands.close.NAME] = capability_handlers.handle_valve_close,
      [capabilities.valve.commands.open.NAME] = capability_handlers.handle_valve_open,
    },
  },
  supported_capabilities = fields.supported_capabilities,
  sub_drivers = {
    switch_utils.lazy_load_if_possible("sub_drivers.aqara_cube"),
    switch_utils.lazy_load("sub_drivers.camera"),
    switch_utils.lazy_load_if_possible("sub_drivers.eve_energy"),
    switch_utils.lazy_load_if_possible("sub_drivers.ikea_scroll"),
    switch_utils.lazy_load_if_possible("sub_drivers.third_reality_mk1")
  }
}

local matter_driver = MatterDriver("matter-switch", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
