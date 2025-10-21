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

function SwitchDeviceConfiguration.assign_profile_for_onoff_ep(device, onoff_ep_id)
  local updated_profile = nil
  local ep = switch_utils.get_endpoint_info(device, onoff_ep_id)
  local primary_dt_id = switch_utils.find_max_subset_device_type(ep, fields.DEVICE_TYPE_ID.LIGHT)
    or (switch_utils.detect_matter_thing(device) and switch_utils.find_max_subset_device_type(ep, fields.DEVICE_TYPE_ID.SWITCH))
    or ep.device_types[1].device_type_id
  updated_profile = fields.device_type_profile_map[primary_dt_id]

  local static_electrical_tags = switch_utils.get_field_for_endpoint(device, fields.ELECTRICAL_TAGS, onoff_ep_id)
  if static_electrical_tags ~= nil then
    updated_profile = string.gsub(updated_profile, "-binary", "") .. static_electrical_tags
  end

  return updated_profile
end

function SwitchDeviceConfiguration.create_child_devices(driver, device, server_onoff_ep_ids, primary_ep_id)
  if #server_onoff_ep_ids == 1 and server_onoff_ep_ids[1] == primary_ep_id then -- no children will be created
    return
  end

  local device_num = 0
  table.sort(server_onoff_ep_ids)
  for _, ep_id in ipairs(server_onoff_ep_ids) do
    device_num = device_num + 1
    if ep_id ~= primary_ep_id then -- don't create a child device that maps to the main endpoint
      local label_and_name = string.format("%s %d", device.label, device_num)
      driver:try_create_device(
        {
          type = "EDGE_CHILD",
          label = label_and_name,
          profile = SwitchDeviceConfiguration.assign_profile_for_onoff_ep(device, ep_id) or "switch-binary",
          parent_device_id = device.id,
          parent_assigned_child_key = string.format("%d", ep_id),
          vendor_provided_label = label_and_name
        }
      )
    end
  end

  -- Persist so that the find_child function is always set on each driver init.
  device:set_field(fields.IS_PARENT_CHILD_DEVICE, true, {persist = true})
  device:set_find_child(switch_utils.find_child)
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

function DeviceConfiguration.match_profile_modular(driver, device)

  local updated_profile = {}

  local st_device_categories = {
    Light = 0,
    SmartPlug = 0,
    Switch = 0,
    RemoteController = 0,
  }

  local device_endpoint_ids = device:get_endpoints()
  device_endpoint_ids.sort()

  for _, ep_id in ipairs(device_endpoint_ids) do
    local ep_info = switch_utils.get_endpoint_info(device, ep_id)

    -- so what we are trying to map is a DT, EP pairing to a cap/comp/category pairing.
    -- kinda most abstractly, we are trying to do more or less an EP-Comp mapping. That's what our APIs support most natively.

    local primary_dt_id = switch_utils.find_max_subset_device_type(ep_info, fields.DEVICE_TYPE_ID.LIGHT)
      -- or (switch_utils.detect_matter_thing(device) and switch_utils.find_max_subset_device_type(ep_info, fields.DEVICE_TYPE_ID.SWITCH))
      or ep_info.device_types[1] and ep_info.device_types[1].device_type_id

    if primary_dt_id == nil then
      device.log.error_with({hub_logs=true}, string.format("No device types found for endpoint %d. Skipping configuration of this endpoint.", ep_info.endpoint_id))
      break
    end

    if switch_utils.tbl_contains(fields.DEVICE_TYPE_ID.LIGHT, primary_dt_id) then
      local main_capabilities = {}
      if primary_dt_id == fields.DEVICE_TYPE_ID.LIGHT.ON_OFF then
        main_capabilities = { capabilities.switch.ID }
      elseif primary_dt_id == fields.DEVICE_TYPE_ID.LIGHT.DIMMABLE then
        main_capabilities = { capabilities.switch.ID, capabilities.switchLevel.ID }
      elseif primary_dt_id == fields.DEVICE_TYPE_ID.LIGHT.COLOR_TEMPERATURE then
        main_capabilities = { capabilities.switch.ID, capabilities.switchLevel.ID, capabilities.colorTemperature.ID }
      elseif primary_dt_id == fields.DEVICE_TYPE_ID.LIGHT.EXTENDED_COLOR then
        main_capabilities = { capabilities.switch.ID, capabilities.switchLevel.ID, capabilities.colorTemperature.ID, capabilities.colorControl.ID }
      end
      updated_profile[ep_info.endpoint_id] = { category = "Light", capabilities = main_capabilities }
      st_device_categories.Light = st_device_categories.Light and st_device_categories.Light + 1 or 1

    elseif primary_dt_id == (fields.DEVICE_TYPE_ID.ON_OFF_PLUG_IN_UNIT or fields.DEVICE_TYPE_ID.MOUNTED_ON_OFF_CONTROL) then
      updated_profile[ep_info.endpoint_id] = { category = "SmartPlug", capabilities = { capabilities.switch.ID } }
      st_device_categories.SmartPlug = st_device_categories.SmartPlug and st_device_categories.SmartPlug + 1 or 1

    elseif primary_dt_id == (fields.DEVICE_TYPE_ID.DIMMABLE_PLUG_IN_UNIT or fields.DEVICE_TYPE_ID.MOUNTED_DIMMABLE_LOAD_CONTROL) then
      updated_profile[ep_info.endpoint_id] = { category = "SmartPlug", capabilities = { capabilities.switch.ID, capabilities.switchLevel.ID } }

    elseif primary_dt_id == fields.DEVICE_TYPE_ID.GENERIC_SWITCH then
      updated_profile[ep_info.endpoint_id] = { category = "RemoteController", capabilities = { capabilities.button.ID } }

    elseif primary_dt_id == fields.DEVICE_TYPE_ID.OCCUPANCY_SENSOR then
      updated_profile[ep_info.endpoint_id] = { capabilities = { capabilities.motionSensor.ID } }

    elseif primary_dt_id == fields.DEVICE_TYPE_ID.LIGHT_SENSOR then
      updated_profile[ep_info.endpoint_id] = { capabilities = { capabilities.illuminanceMeasurement.ID } }

    elseif primary_dt_id == fields.DEVICE_TYPE_ID.TEMPERATURE_SENSOR then
      updated_profile[ep_info.endpoint_id] = { capabilities = { capabilities.temperatureMeasurement.ID } }

    elseif primary_dt_id == fields.DEVICE_TYPE_ID.ELECTRICAL_SENSOR then
      -- have this info ready
      updated_profile[ep_info.endpoint_id] = {}
      local associated_ep_id = switch_utils.get_field_for_endpoint(device, fields.PRIMARY_CHILD_EP, ep_info.endpoint_id)
      local electrical_tags = switch_utils.get_field_for_endpoint(device, fields.ELECTRICAL_TAGS, associated_ep_id)
      local find_substr = function(s, p) return string.find(s or "", p, 1, true) end
      if find_substr(electrical_tags, "power") then
        table.insert(updated_profile[associated_ep_id].capabilities, capabilities.powerMeter.ID)
      end
      if find_substr(electrical_tags, "energy") then
        table.insert(updated_profile[associated_ep_id].capabilities, capabilities.energyMeter.ID)
        table.insert(updated_profile[associated_ep_id].capabilities, capabilities.powerConsumptionReport.ID)
      end
    elseif switch_utils.tbl_contains(fields.DEVICE_TYPE_ID.SWITCH, primary_dt_id) then
      -- implements a Light Switch Controller device type
      local has_on_off_server_cluster = false
      for _, cluster in ipairs(ep_info.clusters) do
        if cluster.cluster_id == clusters.OnOff.ID and cluster.cluster_type == "SERVER" or cluster.cluster_type == "BOTH" then
          has_on_off_server_cluster = true
          break
        end
      end
      if has_on_off_server_cluster then
        local main_capabilities = {}
        if primary_dt_id == fields.DEVICE_TYPE_ID.SWITCH.ON_OFF_LIGHT then
          main_capabilities = { capabilities.switch.ID }
        elseif primary_dt_id == fields.DEVICE_TYPE_ID.SWITCH.DIMMER then
          main_capabilities = { capabilities.switch.ID, capabilities.switchLevel.ID }
        elseif primary_dt_id == fields.DEVICE_TYPE_ID.SWITCH.COLOR_DIMMER then
          main_capabilities = { capabilities.switch.ID, capabilities.switchLevel.ID, capabilities.colorTemperature.ID, capabilities.colorControl.ID }
        end
        updated_profile[ep_info.endpoint_id] = { category = "Switch", capabilities = main_capabilities }
      end
    end
  end

  -- begin creating ST device



end

function DeviceConfiguration.match_profile(driver, device)
  if profiling_data_still_required(device) then return end

  local main_endpoint = switch_utils.find_default_endpoint(device)
  local updated_profile

  local valve_eps = embedded_cluster_utils.get_endpoints(device, clusters.ValveConfigurationAndControl.ID)
  if #valve_eps > 0 then
    updated_profile = "water-valve"
    if #embedded_cluster_utils.get_endpoints(device, clusters.ValveConfigurationAndControl.ID,
      {feature_bitmap = clusters.ValveConfigurationAndControl.types.Feature.LEVEL}) > 0 then
      updated_profile = updated_profile .. "-level"
    end
  end

  local server_onoff_eps = device:get_endpoints(clusters.OnOff.ID, { cluster_type = "SERVER" })
  if #server_onoff_eps > 0 then
    SwitchDeviceConfiguration.create_child_devices(driver, device, server_onoff_eps, main_endpoint)
    updated_profile = SwitchDeviceConfiguration.assign_profile_for_onoff_ep(device, main_endpoint)
    local find_substr = function(s, p) return string.find(s or "", p, 1, true) end
    if find_substr(updated_profile, "light-color-level") and #device:get_endpoints(clusters.FanControl.ID) > 0 then
      updated_profile = "light-color-level-fan"
    elseif find_substr(updated_profile, "light-level") and #device:get_endpoints(clusters.OccupancySensing.ID) > 0 then
      updated_profile = "light-level-motion"
    elseif find_substr(updated_profile, "light-level-colorTemperature") or find_substr(updated_profile, "light-color-level") then
      -- ignore attempts to dynamically profile light-level-colorTemperature and light-color-level devices for now, since
      -- these may lose fingerprinted Kelvin ranges when dynamically profiled.
      return
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

  device:try_update_metadata({profile = updated_profile})
end

return {
  DeviceCfg = DeviceConfiguration,
  ButtonCfg = ButtonDeviceConfiguration
}
