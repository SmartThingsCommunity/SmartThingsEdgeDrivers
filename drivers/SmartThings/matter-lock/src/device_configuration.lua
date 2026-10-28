-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local version = require "version"
local lock_utils = require "lock_utils"

if version.api < 10 then
  clusters.DoorLock = require "DoorLock"
end

local DoorLock = clusters.DoorLock

local device_configuration = {}

device_configuration.battery_support = {
  NO_BATTERY = "NO_BATTERY",
  BATTERY_LEVEL = "BATTERY_LEVEL",
  BATTERY_PERCENTAGE = "BATTERY_PERCENTAGE"
}

device_configuration.profiling_data = {
  BATTERY_SUPPORT = "__BATTERY_SUPPORT",
}

local optional_capability_providers = {}

--- Register extra optional capabilities contributed by a subdriver.
--- The provider is called with the device and returns a list of capability ids, or nil.
--- @param provider fun(device: Device): string[]|nil
function device_configuration.register_optional_capabilities(provider)
  table.insert(optional_capability_providers, provider)
end

local function extra_optional_capabilities(device)
  local extras = {}
  local seen = {}
  for _, provider in ipairs(optional_capability_providers) do
    local caps = provider(device)
    for _, cap_id in ipairs(caps or {}) do
      if not seen[cap_id] then
        seen[cap_id] = true
        table.insert(extras, cap_id)
      end
    end
  end
  return extras
end

local function profiling_data_still_required(device)
  for _, field in pairs(device_configuration.profiling_data) do
    if device:get_field(field) == nil then
      return true
    end
  end
  return false
end

function device_configuration.match_profile_modular(driver, device)
  local enabled_optional_component_capability_pairs = {}
  local main_component_capabilities = {}
  local modular_profile_name = "lock-modular"
  for _, device_ep in pairs(device.endpoints) do
    for _, ep_cluster in pairs(device_ep.clusters) do
      if ep_cluster.cluster_id == DoorLock.ID then
        local clus_has_feature = function(feature_bitmap)
          return DoorLock.are_features_supported(
            feature_bitmap,
            lock_utils.get_field_for_endpoint(device, lock_utils.LATEST_DOOR_LOCK_FEATURE_MAP, device_ep.endpoint_id) or
            ep_cluster.feature_map
          )
        end
        if clus_has_feature(DoorLock.types.Feature.USER) then
          table.insert(main_component_capabilities, capabilities.lockUsers.ID)
        end
        if clus_has_feature(DoorLock.types.Feature.PIN_CREDENTIAL) then
          table.insert(main_component_capabilities, capabilities.lockCredentials.ID)
        end
        if clus_has_feature(DoorLock.types.Feature.WEEK_DAY_ACCESS_SCHEDULES) or
          clus_has_feature(DoorLock.types.Feature.YEAR_DAY_ACCESS_SCHEDULES) then
          table.insert(main_component_capabilities, capabilities.lockSchedules.ID)
        end
        if clus_has_feature(DoorLock.types.Feature.UNBOLT) then
          device:emit_event(capabilities.lock.supportedLockValues({"locked", "unlocked", "unlatched", "not fully locked"}, {visibility = {displayed = false}}))
          device:emit_event(capabilities.lock.supportedLockCommands({"lock", "unlock", "unlatch"}, {visibility = {displayed = false}}))
          modular_profile_name = "lock-modular-embedded-unlatch"
        else
          device:emit_event(capabilities.lock.supportedLockValues({"locked", "unlocked", "not fully locked"}, {visibility = {displayed = false}}))
          device:emit_event(capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
        end
        if clus_has_feature(DoorLock.types.Feature.ALIRO_PROVISIONING) then
          table.insert(main_component_capabilities, capabilities.lockAliro.ID)
        end
        break
      end
    end
  end

  for _, cap_id in ipairs(extra_optional_capabilities(device)) do
    table.insert(main_component_capabilities, cap_id)
  end

  local supported_battery_type = device:get_field(device_configuration.profiling_data.BATTERY_SUPPORT)
  if supported_battery_type == device_configuration.battery_support.BATTERY_LEVEL then
    table.insert(main_component_capabilities, capabilities.batteryLevel.ID)
  elseif supported_battery_type == device_configuration.battery_support.BATTERY_PERCENTAGE then
    table.insert(main_component_capabilities, capabilities.battery.ID)
  end

  table.insert(enabled_optional_component_capability_pairs, {"main", main_component_capabilities})
  if modular_profile_name == "lock-modular-embedded-unlatch"
    or device:supports_capability(capabilities.lockCodes)
    or lock_utils.optional_capabilities_list_changed(enabled_optional_component_capability_pairs, device.profile.components) then
    device:try_update_metadata({profile = modular_profile_name, optional_component_capabilities = enabled_optional_component_capability_pairs})
  end
end

local function match_profile_switch(driver, device)
  local user_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.USER})
  local pin_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.PIN_CREDENTIAL})
  local week_schedule_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.WEEK_DAY_ACCESS_SCHEDULES})
  local year_schedule_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.YEAR_DAY_ACCESS_SCHEDULES})
  local unbolt_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.UNBOLT})

  local profile_name = "lock"
  if #user_eps > 0 then
    profile_name = profile_name .. "-user"
    if #pin_eps > 0 then
      profile_name = profile_name .. "-pin"
    end
    if #week_schedule_eps + #year_schedule_eps > 0 then
      profile_name = profile_name .. "-schedule"
    end
  end
  if #unbolt_eps > 0 then
    profile_name = profile_name .. "-unlatch"
    device:emit_event(capabilities.lock.supportedLockCommands({"lock", "unlock", "unlatch"}, {visibility = {displayed = false}}))
  else
    device:emit_event(capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
  end

  local supported_battery_type = device:get_field(device_configuration.profiling_data.BATTERY_SUPPORT)
  if supported_battery_type == device_configuration.battery_support.BATTERY_LEVEL then
    profile_name = profile_name .. "-batteryLevel"
  elseif supported_battery_type == device_configuration.battery_support.BATTERY_PERCENTAGE then
    profile_name = profile_name .. "-battery"
  end

  device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
  device:try_update_metadata({profile = profile_name})
end

function device_configuration.match_profile(driver, device, ignore_static_profiling)
  if profiling_data_still_required(device) then return end
  if version.api >= 15 and version.rpc >= 9 then
    device_configuration.match_profile_modular(driver, device)
  elseif ignore_static_profiling ~= true then
    match_profile_switch(driver, device)
  end
end

return device_configuration
