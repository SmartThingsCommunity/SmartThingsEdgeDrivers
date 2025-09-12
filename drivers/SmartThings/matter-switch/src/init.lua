-- Copyright 2025 SmartThings
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

local MatterDriver = require "st.matter.driver"
local capabilities = require "st.capabilities"
local device_lib = require "st.device"
local clusters = require "st.matter.clusters"
local log = require "log"
local version = require "version"
local embedded_cluster_utils = require "embedded-cluster-utils"

local fields = require "utils.switch_fields"
local switch_utils = require "utils.switch_utils"

local attribute_handlers = require "generic-handlers.attribute_handlers"
local event_handlers = require "generic-handlers.event_handlers"
local capability_handlers = require "generic-handlers.capability_handlers"
local power_consumption_reporting = require "generic-handlers.power_consumption_report"

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "ElectricalPowerMeasurement"
  clusters.ValveConfigurationAndControl = require "ValveConfigurationAndControl"
end


-- [[ SWITCH CAPABILITY DEVICE CONFIGURATION HELPERS ]]

local function assign_child_profile(device, child_ep)
  local profile

  for _, ep in ipairs(device.endpoints) do
    if ep.endpoint_id == child_ep then
      -- Some devices report multiple device types which are a subset of
      -- a superset device type (For example, Dimmable Light is a superset of
      -- On/Off light). This mostly applies to the four light types, so we will want
      -- to match the profile for the superset device type. This can be done by
      -- matching to the device type with the highest ID
      local id = 0
      for _, dt in ipairs(ep.device_types) do
        id = math.max(id, dt.device_type_id)
      end
      profile = fields.device_type_profile_map[id]
      break
    end
  end

  -- Check if device has an overridden child profile that differs from the profile that would match
  -- the child's device type for the following two cases:
  --   1. To add Electrical Sensor only to the first EDGE_CHILD (light-power-energy-powerConsumption)
  --      for the Aqara Light Switch H2. The profile of the second EDGE_CHILD for this device is
  --      determined in the "for" loop above (e.g., light-binary)
  --   2. The selected profile for the child device matches the initial profile defined in
  --      child_device_profile_overrides
  for id, vendor in pairs(fields.child_device_profile_overrides_per_vendor_id) do
    for _, fingerprint in ipairs(vendor) do
      if device.manufacturer_info.product_id == fingerprint.product_id and
         ((device.manufacturer_info.vendor_id == fields.AQARA_MANUFACTURER_ID and child_ep == 1) or profile == fingerprint.initial_profile) then
         return fingerprint.target_profile
      end
    end
  end

  -- default to "switch-binary" if no profile is found
  return profile or "switch-binary"
end

local function build_child_switch_profiles(driver, device, main_endpoint)
  local num_switch_server_eps = 0
  local parent_child_device = false
  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  table.sort(switch_eps)
  for idx, ep in ipairs(switch_eps) do
    if device:supports_server_cluster(clusters.OnOff.ID, ep) then
      num_switch_server_eps = num_switch_server_eps + 1
      if ep ~= main_endpoint then -- don't create a child device that maps to the main endpoint
        local name = string.format("%s %d", device.label, num_switch_server_eps)
        local child_profile = assign_child_profile(device, ep)
        driver:try_create_device(
          {
            type = "EDGE_CHILD",
            label = name,
            profile = child_profile,
            parent_device_id = device.id,
            parent_assigned_child_key = string.format("%d", ep),
            vendor_provided_label = name
          }
        )
        parent_child_device = true
        if idx == 1 and string.find(child_profile, "energy") then
          -- when energy management is defined in the root endpoint(0), replace it with the first switch endpoint and process it.
          device:set_field(fields.ENERGY_MANAGEMENT_ENDPOINT, ep, {persist = true})
        end
      end
    end
  end

  -- If the device is a parent child device, set the find_child function on init. This is persisted because initialize_buttons_and_switches
  -- is only run once, but find_child function should be set on each driver init.
  if parent_child_device then
    device:set_field(fields.IS_PARENT_CHILD_DEVICE, true, {persist = true})
  end

  -- this is needed in initialize_buttons_and_switches
  return num_switch_server_eps
end

local function handle_light_switch_with_onOff_server_clusters(device, main_endpoint)
  local cluster_id = 0
  for _, ep in ipairs(device.endpoints) do
    -- main_endpoint only supports server cluster by definition of get_endpoints()
    if main_endpoint == ep.endpoint_id then
      for _, dt in ipairs(ep.device_types) do
        -- no device type that is not in the switch subset should be considered.
        if (fields.ON_OFF_SWITCH_ID <= dt.device_type_id and dt.device_type_id <= fields.ON_OFF_COLOR_DIMMER_SWITCH_ID) then
          cluster_id = math.max(cluster_id, dt.device_type_id)
        end
      end
      break
    end
  end

  if fields.device_type_profile_map[cluster_id] then
    device:try_update_metadata({profile = fields.device_type_profile_map[cluster_id]})
  end
end


-- [[ BUTTON CAPABILITY DEVICE CONFIGURATION HELPERS ]]

local function build_button_profile(device, main_endpoint, num_button_eps)
  local profile_name = string.gsub(num_button_eps .. "-button", "1%-", "") -- remove the "1-" in a device with 1 button ep
  if switch_utils.device_type_supports_button_switch_combination(device, main_endpoint) then
    profile_name = "light-level-" .. profile_name
  end
  local battery_supported = #device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY}) > 0
  if battery_supported then -- battery profiles are configured later, in power_source_attribute_list_handler
    device:send(clusters.PowerSource.attributes.AttributeList:read(device))
  else
    device:try_update_metadata({profile = profile_name})
  end
end

local function build_button_component_map(device, main_endpoint, button_eps)
  -- create component mapping on the main profile button endpoints
  table.sort(button_eps)
  local component_map = {}
  component_map["main"] = main_endpoint
  for component_num, ep in ipairs(button_eps) do
    if ep ~= main_endpoint then
      local button_component = "button"
      if #button_eps > 1 then
        button_component = button_component .. component_num
      end
      component_map[button_component] = ep
    end
  end
  device:set_field(fields.COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
end

local function configure_buttons(device)
  local ms_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  local msr_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_RELEASE})
  local msl_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS})
  local msm_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS})

  for _, ep in ipairs(ms_eps) do
    if device.profile.components[switch_utils.endpoint_to_component(device, ep)] then
      device.log.info_with({hub_logs=true}, string.format("Configuring Supported Values for generic switch endpoint %d", ep))
      local supportedButtonValues_event
      -- this ordering is important, since MSM & MSL devices must also support MSR
      if switch_utils.tbl_contains(msm_eps, ep) then
        supportedButtonValues_event = nil -- deferred to the max press handler
        device:send(clusters.Switch.attributes.MultiPressMax:read(device, ep))
        switch_utils.set_field_for_endpoint(device, fields.SUPPORTS_MULTI_PRESS, ep, true, {persist = true})
      elseif switch_utils.tbl_contains(msl_eps, ep) then
        supportedButtonValues_event = capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})
      elseif switch_utils.tbl_contains(msr_eps, ep) then
        supportedButtonValues_event = capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})
        switch_utils.set_field_for_endpoint(device, fields.EMULATE_HELD, ep, true, {persist = true})
      else -- this switch endpoint only supports momentary switch, no release events
        supportedButtonValues_event = capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})
        switch_utils.set_field_for_endpoint(device, fields.INITIAL_PRESS_ONLY, ep, true, {persist = true})
      end

      if supportedButtonValues_event then
        device:emit_event_for_endpoint(ep, supportedButtonValues_event)
      end
      device:emit_event_for_endpoint(ep, capabilities.button.button.pushed({state_change = false}))
    else
      device.log.info_with({hub_logs=true}, string.format("Component not found for generic switch endpoint %d. Skipping Supported Value configuration", ep))
    end
  end
end


-- [[ PROFILE MATCHING AND CONFIGURATIONS ]] --

local function initialize_buttons_and_switches(driver, device, main_endpoint)
  local profile_found = false
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  if switch_utils.tbl_contains(fields.STATIC_BUTTON_PROFILE_SUPPORTED, #button_eps) then
    build_button_profile(device, main_endpoint, #button_eps)
    -- All button endpoints found will be added as additional components in the profile containing the main_endpoint.
    -- The resulting endpoint to component map is saved in the COMPONENT_TO_ENDPOINT_MAP field
    build_button_component_map(device, main_endpoint, button_eps)
    configure_buttons(device)
    profile_found = true
  end

  -- Without support for bindings, only clusters that are implemented as server are counted. This count is handled
  -- while building switch child profiles
  local num_switch_server_eps = build_child_switch_profiles(driver, device, main_endpoint)

  -- We do not support the Light Switch device types because they require OnOff to be implemented as 'client', which requires us to support bindings.
  -- However, this workaround profiles devices that claim to be Light Switches, but that break spec and implement OnOff as 'server'.
  -- Note: since their device type isn't supported, these devices join as a matter-thing.
  if num_switch_server_eps > 0 and switch_utils.detect_matter_thing(device) then
    handle_light_switch_with_onOff_server_clusters(device, main_endpoint)
    profile_found = true
  end
  return profile_found
end

local function match_profile(driver, device)
  local main_endpoint = switch_utils.find_default_endpoint(device)
  -- initialize the main device card with buttons if applicable, and create child devices as needed for multi-switch devices.
  local profile_found = initialize_buttons_and_switches(driver, device, main_endpoint)
  if device:get_field(fields.IS_PARENT_CHILD_DEVICE) then
    device:set_find_child(switch_utils.find_child)
  end
  if profile_found then
    return
  end

  local fan_eps = device:get_endpoints(clusters.FanControl.ID)
  local level_eps = device:get_endpoints(clusters.LevelControl.ID)
  local energy_eps = embedded_cluster_utils.get_endpoints(device, clusters.ElectricalEnergyMeasurement.ID)
  local power_eps = embedded_cluster_utils.get_endpoints(device, clusters.ElectricalPowerMeasurement.ID)
  local valve_eps = embedded_cluster_utils.get_endpoints(device, clusters.ValveConfigurationAndControl.ID)
  local profile_name = nil
  local level_support = ""
  if #level_eps > 0 then
    level_support = "-level"
  end
  if #energy_eps > 0 and #power_eps > 0 then
    profile_name = "plug" .. level_support .. "-power-energy-powerConsumption"
  elseif #energy_eps > 0 then
    profile_name = "plug" .. level_support .. "-energy-powerConsumption"
  elseif #power_eps > 0 then
    profile_name = "plug" .. level_support .. "-power"
  elseif #valve_eps > 0 then
    profile_name = "water-valve"
    if #embedded_cluster_utils.get_endpoints(device, clusters.ValveConfigurationAndControl.ID,
      {feature_bitmap = clusters.ValveConfigurationAndControl.types.Feature.LEVEL}) > 0 then
      profile_name = profile_name .. "-level"
    end
  elseif #fan_eps > 0 then
    profile_name = "light-color-level-fan"
  end
  if profile_name then
    device:try_update_metadata({ profile = profile_name })
  end
end

-- [[ LIFECYCLE HANDLERS ]] --

local SwitchLifecycleHandlers = {}

function SwitchLifecycleHandlers.device_added(driver, device)
  -- refresh child devices to get an initial attribute state for OnOff in case child device
  -- was created after the initial subscription report
  if device.network_type == device_lib.NETWORK_TYPE_CHILD then
    device:send(clusters.OnOff.attributes.OnOff:read(device))
  end

  print("ok ok")
  -- call device init in case init is not called after added due to device caching
  SwitchLifecycleHandlers.device_init(driver, device)
end

function SwitchLifecycleHandlers.do_configure(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and not switch_utils.detect_bridge(device) then
    match_profile(driver, device)
  end
end

function SwitchLifecycleHandlers.driver_switched(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and not switch_utils.detect_bridge(device) then
    match_profile(driver, device)
  end
end

function SwitchLifecycleHandlers.info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    device:subscribe()
    local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
    if #button_eps > 0 and device.network_type == device_lib.NETWORK_TYPE_MATTER then
      configure_buttons(device)
    end
  end
end

function SwitchLifecycleHandlers.device_removed(driver, device)
  device.log.info("device removed")
  power_consumption_reporting.delete_import_poll_schedule(device)
end

function SwitchLifecycleHandlers.device_init(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then
    switch_utils.check_field_name_updates(device)
    device:set_component_to_endpoint_fn(switch_utils.component_to_endpoint)
    device:set_endpoint_to_component_fn(switch_utils.endpoint_to_component)
    if device:get_field(fields.IS_PARENT_CHILD_DEVICE) then
      print("ok ok 2")
      device:set_find_child(switch_utils.find_child)
    end
    print("ok ok 2")
    local main_endpoint = switch_utils.find_default_endpoint(device)
    print("ok ok 3")
    -- ensure subscription to all endpoint attributes- including those mapped to child devices
    for idx, ep in ipairs(device.endpoints) do
      if ep.endpoint_id ~= main_endpoint then
        if device:supports_server_cluster(clusters.OnOff.ID, ep) then
          local child_profile = assign_child_profile(device, ep)
          if idx == 1 and string.find(child_profile, "energy") then
            -- when energy management is defined in the root endpoint(0), replace it with the first switch endpoint and process it.
            device:set_field(fields.ENERGY_MANAGEMENT_ENDPOINT, ep, {persist = true})
          end
        end
        local id = 0
        for _, dt in ipairs(ep.device_types) do
          id = math.max(id, dt.device_type_id)
        end
        for _, attr in pairs(fields.device_type_attribute_map[id] or {}) do
          if id == fields.GENERIC_SWITCH_ID and
             attr ~= clusters.PowerSource.attributes.BatPercentRemaining and
             attr ~= clusters.PowerSource.attributes.BatChargeLevel then
            device:add_subscribed_event(attr)
          else
            device:add_subscribed_attribute(attr)
          end
        end
      end
    end
    print("ok ok 4")

    device:subscribe()
  end
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
      [clusters.ElectricalEnergyMeasurement.ID] = {
        [clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported.ID] = attribute_handlers.energy_imported_factory(true),
        [clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported.ID] = attribute_handlers.energy_imported_factory(false),
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
    require("aqara-cube"),
    require("eve-energy"),
    require("third-reality-mk1")
  }
}

local matter_driver = MatterDriver("matter-switch", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
