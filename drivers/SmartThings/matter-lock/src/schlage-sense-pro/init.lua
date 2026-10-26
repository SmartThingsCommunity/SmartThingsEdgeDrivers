-- Copyright 2026 SmartThings, Inc.
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

--- Subdriver for Allegion / Schlage Sense Pro UWB Door Lock
---
--- Provides integration for:
--- - lockUwbApproachSettings (Field of View: Front+Left+Right, Front+Left, Front+Right, Front only)
--- - lockUwbModeSettings (Intent Mode: Unlock on Approach, Unlock on Arrival, Unlock on Lock Interaction)
--- - Profile management with lock-modular-uwb-settings
--- - Communication via Matter Manufacturer-Specific Cluster (to be detailed by Allegion)

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local lock_utils = require "lock_utils"
local constants = require "schlage-sense-pro.constants"

local DoorLock = clusters.DoorLock

-- Resolve or build capability representations
local lockUwbApproachSettings = constants.get_lock_uwb_approach_settings_capability()
local lockUwbModeSettings = constants.get_lock_uwb_mode_settings_capability()

-------------------------------------------------------------------------------------
-- Helper: Endpoint Resolution
-- [VERIFICATION REQUIRED BY ALLEGION]
-------------------------------------------------------------------------------------

--- Find the target endpoint for Schlage UWB custom cluster communication.
--- [PLACEHOLDER - VERIFICATION REQUIRED BY ALLEGION]:
--- Verify the endpoint hosting the manufacturer custom cluster on the physical lock.
--- By default, it searches for an endpoint supporting the custom cluster ID,
--- or falls back to the DoorLock cluster endpoint (typically 1).
local function find_schlage_endpoint(device)
  local custom_eps = device:get_endpoints(constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID)
  if #custom_eps > 0 then
    return custom_eps[1]
  end
  local lock_eps = device:get_endpoints(DoorLock.ID)
  if #lock_eps > 0 then
    return lock_eps[1]
  end
  return device.MATTER_DEFAULT_ENDPOINT or 1
end

-------------------------------------------------------------------------------------
-- Manufacturer-Specific Cluster Communication (Scaffold for Allegion)
-- [PLACEHOLDER - ACTION REQUIRED BY ALLEGION]
-------------------------------------------------------------------------------------

--- Read Field of View attribute from Schlage Custom Cluster.
--- @param device st.matter.Device
local function read_field_of_view(device)
  local ep = find_schlage_endpoint(device)
  device.log.info(string.format("Reading Schlage UWB Field of View (Cluster: 0x%08X, Attr: 0x%04X, EP: %d)",
    constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_FIELD_OF_VIEW_ID, ep))
  device:send(cluster_base.read(device, ep, constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_FIELD_OF_VIEW_ID, nil))
end

--- Write Field of View attribute to Schlage Custom Cluster.
--- [PLACEHOLDER - DATA TYPE]:
--- Scaffold uses data_types.Uint8 by default. If the cluster attribute is defined as
--- data_types.Enum8 or another type, update data_types.Uint8 accordingly.
--- @param device st.matter.Device
--- @param raw_value number (0: Front+Left+Right, 1: Front+Left, 2: Front+Right, 3: Front only)
local function write_field_of_view(device, raw_value)
  local ep = find_schlage_endpoint(device)
  device.log.info(string.format("Writing Schlage UWB Field of View: %d (Cluster: 0x%08X, Attr: 0x%04X, EP: %d)",
    raw_value, constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_FIELD_OF_VIEW_ID, ep))
  -- [PLACEHOLDER - DATA TYPE]: Update to data_types.Enum8 or matching cluster data type if needed
  local data = data_types.validate_or_build_type(raw_value, data_types.Uint8)
  device:send(cluster_base.write(device, ep, constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_FIELD_OF_VIEW_ID, nil, data))
end

--- Read Intent Mode attribute from Schlage Custom Cluster.
--- @param device st.matter.Device
local function read_intent_mode(device)
  local ep = find_schlage_endpoint(device)
  device.log.info(string.format("Reading Schlage UWB Intent Mode (Cluster: 0x%08X, Attr: 0x%04X, EP: %d)",
    constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_INTENT_MODE_ID, ep))
  device:send(cluster_base.read(device, ep, constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_INTENT_MODE_ID, nil))
end

--- Write Intent Mode attribute to Schlage Custom Cluster.
--- [PLACEHOLDER - DATA TYPE]:
--- Scaffold uses data_types.Uint8 by default. If the cluster attribute is defined as
--- data_types.Enum8 or another type, update data_types.Uint8 accordingly.
--- @param device st.matter.Device
--- @param raw_value number (0: Unlock on Approach, 1: Unlock on Arrival, 2: Unlock on Lock Interaction)
local function write_intent_mode(device, raw_value)
  local ep = find_schlage_endpoint(device)
  device.log.info(string.format("Writing Schlage UWB Intent Mode: %d (Cluster: 0x%08X, Attr: 0x%04X, EP: %d)",
    raw_value, constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_INTENT_MODE_ID, ep))
  -- [PLACEHOLDER - DATA TYPE]: Update to data_types.Enum8 or matching cluster data type if needed
  local data = data_types.validate_or_build_type(raw_value, data_types.Uint8)
  device:send(cluster_base.write(device, ep, constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_INTENT_MODE_ID, nil, data))
end

--- [PLACEHOLDER - COMMAND INVOKE ALTERNATIVE]:
--- If the cluster uses Matter Invoke Commands instead of Attribute Writes,
--- use the template functions below and invoke them from handle_set_* instead:
--[[
local function invoke_set_field_of_view(device, raw_value)
  local ep = find_schlage_endpoint(device)
  local cmd_params = { [0] = raw_value }
  local req = cluster_base.build_cluster_command(nil, device, cmd_params, ep,
    constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.CMD_SET_FIELD_OF_VIEW_ID, false, false)
  device:send(req)
end

local function invoke_set_intent_mode(device, raw_value)
  local ep = find_schlage_endpoint(device)
  local cmd_params = { [0] = raw_value }
  local req = cluster_base.build_cluster_command(nil, device, cmd_params, ep,
    constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.CMD_SET_INTENT_MODE_ID, false, false)
  device:send(req)
end
--]]

-------------------------------------------------------------------------------------
-- Capability Event Helpers
-------------------------------------------------------------------------------------

local function emit_supported_values(device)
  if device:supports_capability_by_id(constants.CAPABILITY_LOCK_UWB_APPROACH_SETTINGS) then
    device:emit_event(lockUwbApproachSettings.supportedApproachDirections(
      constants.SUPPORTED_APPROACH_DIRECTIONS, { visibility = { displayed = false } }
    ))
  end
  if device:supports_capability_by_id(constants.CAPABILITY_LOCK_UWB_MODE_SETTINGS) then
    device:emit_event(lockUwbModeSettings.supportedIntentModes(
      constants.SUPPORTED_INTENT_MODES, { visibility = { displayed = false } }
    ))
  end
end

-------------------------------------------------------------------------------------
-- Matter Attribute Handlers (Device -> SmartThings Hub)
-------------------------------------------------------------------------------------

--- Handles Field of View reports from the Schlage Custom Cluster
local function field_of_view_attr_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    local raw_val = ib.data.value
    local enum_val = constants.RAW_TO_APPROACH_DIRECTION[raw_val]
    device.log.info(string.format("Schlage UWB Field of View report: raw=%s, enum=%s", tostring(raw_val), tostring(enum_val)))
    if enum_val then
      device:emit_event(lockUwbApproachSettings.approachDirection(enum_val))
    else
      device.log.warn(string.format("Unknown Schlage UWB Field of View value: %s", tostring(raw_val)))
    end
  end
end

--- Handles Intent Mode reports from the Schlage Custom Cluster
local function intent_mode_attr_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    local raw_val = ib.data.value
    local enum_val = constants.RAW_TO_INTENT_MODE[raw_val]
    device.log.info(string.format("Schlage UWB Intent Mode report: raw=%s, enum=%s", tostring(raw_val), tostring(enum_val)))
    if enum_val then
      device:emit_event(lockUwbModeSettings.intentMode(enum_val))
    else
      device.log.warn(string.format("Unknown Schlage UWB Intent Mode value: %s", tostring(raw_val)))
    end
  end
end

-------------------------------------------------------------------------------------
-- Capability Command Handlers (SmartThings App -> Device)
-------------------------------------------------------------------------------------

--- Handler for lockUwbApproachSettings:setApproachDirection command
local function handle_set_approach_direction(driver, device, command)
  local val = command.args.approachDirection
  device.log.info(string.format("Handling setApproachDirection command: %s", tostring(val)))

  local raw_val = nil
  if type(val) == "number" then
    raw_val = val
  elseif type(val) == "string" then
    raw_val = constants.APPROACH_DIRECTION_TO_RAW[val]
  end

  if raw_val ~= nil and constants.RAW_TO_APPROACH_DIRECTION[raw_val] ~= nil then
    write_field_of_view(device, raw_val)
    -- Optimistic event update for immediate UX feedback
    local enum_val = constants.RAW_TO_APPROACH_DIRECTION[raw_val]
    device:emit_event(lockUwbApproachSettings.approachDirection(enum_val))
  else
    device.log.error(string.format("Invalid approachDirection argument: %s", tostring(val)))
  end
end

--- Handler for lockUwbModeSettings:setIntentMode command
local function handle_set_intent_mode(driver, device, command)
  local val = command.args.intentMode
  device.log.info(string.format("Handling setIntentMode command: %s", tostring(val)))

  local raw_val = nil
  if type(val) == "number" then
    raw_val = val
  elseif type(val) == "string" then
    raw_val = constants.INTENT_MODE_TO_RAW[val]
  end

  if raw_val ~= nil and constants.RAW_TO_INTENT_MODE[raw_val] ~= nil then
    write_intent_mode(device, raw_val)
    -- Optimistic event update for immediate UX feedback
    local enum_val = constants.RAW_TO_INTENT_MODE[raw_val]
    device:emit_event(lockUwbModeSettings.intentMode(enum_val))
  else
    device.log.error(string.format("Invalid intentMode argument: %s", tostring(val)))
  end
end

--- Handler for refresh capability
local function handle_refresh(driver, device, command)
  device.log.info("Refreshing Schlage Sense Pro UWB and Lock State")
  -- 1. Standard Door Lock state refresh
  device:send(DoorLock.attributes.LockState:read(device))
  device:set_field(lock_utils.BUSY_STATE, false, { persist = true })

  -- 2. Schlage UWB settings refresh
  read_field_of_view(device)
  read_intent_mode(device)
end

-------------------------------------------------------------------------------------
-- Device Lifecycle Handlers
-------------------------------------------------------------------------------------

local function configure_profile(device)
  local modular_profile_name = "lock-modular-uwb-settings"
  local main_component_capabilities = {
    constants.CAPABILITY_LOCK_UWB_APPROACH_SETTINGS,
    constants.CAPABILITY_LOCK_UWB_MODE_SETTINGS,
  }

  -- Check DoorLock features
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
        if clus_has_feature(DoorLock.types.Feature.ALIRO_PROVISIONING) then
          table.insert(main_component_capabilities, capabilities.lockAliro.ID)
        end
        break
      end
    end
  end

  local supported_battery_type = device:get_field("__BATTERY_SUPPORT")
  if supported_battery_type == "BATTERY_LEVEL" then
    table.insert(main_component_capabilities, capabilities.batteryLevel.ID)
  elseif supported_battery_type == "BATTERY_PERCENTAGE" then
    table.insert(main_component_capabilities, capabilities.battery.ID)
  end

  local enabled_optional = { { "main", main_component_capabilities } }
  device:try_update_metadata({
    profile = modular_profile_name,
    optional_component_capabilities = enabled_optional
  })
end

local function device_init(driver, device)
  device.log.info("Schlage Sense Pro UWB subdriver device_init")
  -- Chain base driver initialization if available
  if driver.lifecycle_handlers and driver.lifecycle_handlers.init then
    driver.lifecycle_handlers.init(driver, device)
  end

  -- Automatically migrate previously onboarded devices (e.g. paired prior to driver update
  -- under lock-modular) that do not yet have lockUwbApproachSettings to lock-modular-uwb-settings.
  if not device:supports_capability_by_id(constants.CAPABILITY_LOCK_UWB_APPROACH_SETTINGS) then
    device.log.info("Migrating existing Schlage Sense Pro device profile to lock-modular-uwb-settings")
    configure_profile(device)
    emit_supported_values(device)
    read_field_of_view(device)
    read_intent_mode(device)
  end
end

local function device_added(driver, device)
  device.log.info("Schlage Sense Pro UWB subdriver device_added")
  if driver.lifecycle_handlers and driver.lifecycle_handlers.added then
    driver.lifecycle_handlers.added(driver, device)
  end

  emit_supported_values(device)
  read_field_of_view(device)
  read_intent_mode(device)
end

local function do_configure(driver, device)
  device.log.info("Schlage Sense Pro UWB subdriver do_configure")
  configure_profile(device)

  emit_supported_values(device)
  read_field_of_view(device)
  read_intent_mode(device)

  if driver.lifecycle_handlers and driver.lifecycle_handlers.doConfigure then
    driver.lifecycle_handlers.doConfigure(driver, device)
  end
end

local function driver_switched(driver, device)
  device.log.info("Schlage Sense Pro UWB subdriver driver_switched")
  configure_profile(device)
  emit_supported_values(device)
  read_field_of_view(device)
  read_intent_mode(device)
  device:try_update_metadata({ provisioning_state = "PROVISIONED" })
end

local function info_changed(driver, device, event, args)
  device.log.info("Schlage Sense Pro UWB subdriver info_changed")
  if driver.lifecycle_handlers and driver.lifecycle_handlers.infoChanged then
    driver.lifecycle_handlers.infoChanged(driver, device, event, args)
  end
end

-------------------------------------------------------------------------------------
-- Subdriver Template Definition
-------------------------------------------------------------------------------------

local schlage_sense_pro_subdriver = {
  NAME = "schlage-sense-pro",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    driverSwitched = driver_switched,
    infoChanged = info_changed,
  },
  matter_handlers = {
    attr = {
      [constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID] = {
        [constants.ATTR_FIELD_OF_VIEW_ID] = field_of_view_attr_handler,
        [constants.ATTR_INTENT_MODE_ID] = intent_mode_attr_handler,
      }
    },
  },
  capability_handlers = {
    [constants.CAPABILITY_LOCK_UWB_APPROACH_SETTINGS] = {
      [lockUwbApproachSettings.commands.setApproachDirection.NAME] = handle_set_approach_direction,
    },
    [constants.CAPABILITY_LOCK_UWB_MODE_SETTINGS] = {
      [lockUwbModeSettings.commands.setIntentMode.NAME] = handle_set_intent_mode,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = handle_refresh,
    },
  },
  supported_capabilities = {
    lockUwbApproachSettings,
    lockUwbModeSettings,
  },
  can_handle = require("schlage-sense-pro.can_handle"),
}

return schlage_sense_pro_subdriver
