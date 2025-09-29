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

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "utils.embedded_cluster_utils"
local version = require "version"

local fields = require "utils.switch_fields"
local switch_utils = require "utils.switch_utils"

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded_clusters.ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "embedded_clusters.ElectricalPowerMeasurement"
  clusters.ValveConfigurationAndControl = require "embedded_clusters.ValveConfigurationAndControl"
end

local DeviceConfiguration = {}
local SwitchDeviceConfiguration = {}
local ButtonDeviceConfiguration = {}

function SwitchDeviceConfiguration.assign_switch_profile(device, switch_ep, opts)
  local profile

  for _, ep in ipairs(device.endpoints) do
    if ep.endpoint_id == switch_ep then
      -- Some devices report multiple device types which are a subset of
      -- a superset device type (For example, Dimmable Light is a superset of
      -- On/Off light). This mostly applies to the four light types, so we will want
      -- to match the profile for the superset device type. This can be done by
      -- matching to the device type with the highest ID
      -- Note: Electrical Sensor does not follow the above logic, so it's ignored
      local id = 0
      for _, dt in ipairs(ep.device_types) do
        if dt.device_type_id ~= fields.ELECTRICAL_SENSOR_ID then
          id = math.max(id, dt.device_type_id)
        end
      end
      profile = fields.device_type_profile_map[id]
      break
    end
  end

  local electrical_tags = switch_utils.get_field_for_endpoint(device, fields.ELECTRICAL_TAGS, switch_ep)
  if electrical_tags ~= nil and (profile == "plug-binary" or profile == "plug-level" or profile == "light-binary") then
    profile = string.gsub(profile, "-binary", "") .. electrical_tags
  end

  if opts and opts.is_child_device then
    -- Check if device has a profile override that differs from its generically chosen profile
    return switch_utils.check_vendor_overrides(device.manufacturer_info, "initial_profile", profile, "target_profile")
       or profile
       or "switch-binary" -- default to "switch-binary" if no child profile is found
  end
  return profile
end

function SwitchDeviceConfiguration.create_child_switch_devices(driver, device, switch_eps, main_endpoint)
  local switch_server_ep = 0
  local parent_child_device = false

  table.sort(switch_eps)
  for _, ep in ipairs(switch_eps) do
    switch_server_ep = switch_server_ep + 1
    if ep ~= main_endpoint then -- don't create a child device that maps to the main endpoint
      local name = string.format("%s %d", device.label, switch_server_ep)
      local child_profile = SwitchDeviceConfiguration.assign_switch_profile(device, ep, { is_child_device = true })
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
    end
  end

  -- Persist so that the find_child function is always set on each driver init.
  if parent_child_device then
    device:set_field(fields.IS_PARENT_CHILD_DEVICE, true, {persist = true})
    device:set_find_child(switch_utils.find_child)
  end
end

function SwitchDeviceConfiguration.match_light_switch_device_profile(device, main_endpoint)
  local cluster_id = 0
  for _, ep in ipairs(device.endpoints) do
    -- main_endpoint only supports server cluster by definition of get_endpoints()
    if main_endpoint == ep.endpoint_id then
      for _, dt in ipairs(ep.device_types) do
        -- no device type that is not in the switch subset should be considered.
        if (fields.DEVICE_TYPE_ID.ON_OFF_LIGHT_SWITCH <= dt.device_type_id and dt.device_type_id <= fields.DEVICE_TYPE_ID.COLOR_DIMMER_SWITCH) then
          cluster_id = math.max(cluster_id, dt.device_type_id)
        end
      end
      return fields.device_type_profile_map[cluster_id]
    end
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

local function profiling_data_still_required(device)
  for _, field in pairs(fields.profiling_data) do
    if device:get_field(field) == nil then
      return true -- data still required if a field is nil
    end
  end
  return false
end

function DeviceConfiguration.match_profile(driver, device)
  if profiling_data_still_required(device) then return end
  local main_endpoint = switch_utils.find_default_endpoint(device)
  local profile_name = nil

  local server_onoff_eps = device:get_endpoints(clusters.OnOff.ID, { cluster_type = "SERVER" })
  if #server_onoff_eps > 0 then
    SwitchDeviceConfiguration.create_child_switch_devices(driver, device, server_onoff_eps, main_endpoint)
    -- workaround: finds a profile for devices of the Light Switch device type set that break spec and implement OnOff as 'server' instead of 'client'.
    -- note: since the Light Switch device set isn't supported, these devices join as a matter-thing.
    if switch_utils.detect_matter_thing(device) then
      profile_name = SwitchDeviceConfiguration.match_light_switch_device_profile(device, main_endpoint)
    end
  end

  -- initialize the main device card with buttons if applicable
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  if switch_utils.tbl_contains(fields.STATIC_BUTTON_PROFILE_SUPPORTED, #button_eps) then
    ButtonDeviceConfiguration.update_button_profile(device, main_endpoint, #button_eps)
    -- All button endpoints found will be added as additional components in the profile containing the main_endpoint.
    ButtonDeviceConfiguration.update_button_component_map(device, main_endpoint, button_eps)
    ButtonDeviceConfiguration.configure_buttons(device)
    return
  end

  local fan_eps = device:get_endpoints(clusters.FanControl.ID)
  local valve_eps = embedded_cluster_utils.get_endpoints(device, clusters.ValveConfigurationAndControl.ID)
  local profile_name = nil
  if #valve_eps > 0 then
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
    return
  end

  -- after doing all previous profiling steps, attempt to re-profile main/parent switch/plug device
  profile_name = SwitchDeviceConfiguration.assign_switch_profile(device, main_endpoint)
  -- ignore attempts to dynamically profile light-level-colorTemperature and light-color-level devices for now, since
  -- these may lose fingerprinted Kelvin ranges when dynamically profiled.
  if profile_name and profile_name ~= "light-level-colorTemperature" and profile_name ~= "light-color-level" then
    if profile_name == "light-level" and #device:get_endpoints(clusters.OccupancySensing.ID) > 0 then
      profile_name = "light-level-motion"
    end
    device:try_update_metadata({profile = profile_name})
  end
end

return {
  DeviceCfg = DeviceConfiguration,
  SwitchCfg = SwitchDeviceConfiguration,
  ButtonCfg = ButtonDeviceConfiguration
}
