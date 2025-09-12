local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "utils.embedded-cluster-utils"
local version = require "version"

local fields = require "utils.switch_fields"
local switch_utils = require "utils.switch_utils"

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded-clusters.ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "embedded-clusters.ElectricalPowerMeasurement"
  clusters.ValveConfigurationAndControl = require "embedded-clusters.ValveConfigurationAndControl"
end

local DeviceConfiguration = {}
local SwitchDeviceConfiguration = {}
local ButtonDeviceConfiguration = {}

function SwitchDeviceConfiguration.assign_child_profile(device, child_ep)
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

function SwitchDeviceConfiguration.create_child_switch_devices(driver, device, main_endpoint)
  local num_switch_server_eps = 0
  local parent_child_device = false
  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  table.sort(switch_eps)
  for idx, ep in ipairs(switch_eps) do
    if device:supports_server_cluster(clusters.OnOff.ID, ep) then
      num_switch_server_eps = num_switch_server_eps + 1
      if ep ~= main_endpoint then -- don't create a child device that maps to the main endpoint
        local name = string.format("%s %d", device.label, num_switch_server_eps)
        local child_profile = SwitchDeviceConfiguration.assign_child_profile(device, ep)
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

function SwitchDeviceConfiguration.update_devices_with_onOff_server_clusters(device, main_endpoint)
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

function ButtonDeviceConfiguration.update_button_profile(device, main_endpoint, num_button_eps)
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

function ButtonDeviceConfiguration.update_button_component_map(device, main_endpoint, button_eps)
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


function ButtonDeviceConfiguration.configure_buttons(device)
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

function DeviceConfiguration.initialize_buttons_and_switches(driver, device, main_endpoint)
  local profile_found = false
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  if switch_utils.tbl_contains(fields.STATIC_BUTTON_PROFILE_SUPPORTED, #button_eps) then
    ButtonDeviceConfiguration.update_button_profile(device, main_endpoint, #button_eps)
    -- All button endpoints found will be added as additional components in the profile containing the main_endpoint.
    -- The resulting endpoint to component map is saved in the COMPONENT_TO_ENDPOINT_MAP field
    ButtonDeviceConfiguration.update_button_component_map(device, main_endpoint, button_eps)
    ButtonDeviceConfiguration.configure_buttons(device)
    profile_found = true
  end

  -- Without support for bindings, only clusters that are implemented as server are counted. This count is handled
  -- while building switch child profiles
  local num_switch_server_eps = SwitchDeviceConfiguration.create_child_switch_devices(driver, device, main_endpoint)

  -- We do not support the Light Switch device types because they require OnOff to be implemented as 'client', which requires us to support bindings.
  -- However, this workaround profiles devices that claim to be Light Switches, but that break spec and implement OnOff as 'server'.
  -- Note: since their device type isn't supported, these devices join as a matter-thing.
  if num_switch_server_eps > 0 and switch_utils.detect_matter_thing(device) then
    SwitchDeviceConfiguration.update_devices_with_onOff_server_clusters(device, main_endpoint)
    profile_found = true
  end
  return profile_found
end

function DeviceConfiguration.match_profile(driver, device)
  local main_endpoint = switch_utils.find_default_endpoint(device)
  -- initialize the main device card with buttons if applicable, and create child devices as needed for multi-switch devices.
  local profile_found = DeviceConfiguration.initialize_buttons_and_switches(driver, device, main_endpoint)
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

return {
  DeviceCfg = DeviceConfiguration,
  SwitchCfg = SwitchDeviceConfiguration,
  ButtonCfg = ButtonDeviceConfiguration
}
