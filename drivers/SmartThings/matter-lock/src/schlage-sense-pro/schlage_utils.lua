-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.matter.clusters"
local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local constants = require "schlage-sense-pro.constants"

local DoorLock = clusters.DoorLock
local lockUwbApproachSettings = constants.get_lock_uwb_approach_settings_capability()
local lockUwbModeSettings = constants.get_lock_uwb_mode_settings_capability()

local schlage_utils = {}

--- Find the endpoint that hosts the Schlage UWB custom cluster.
--- Returns nil when neither the custom cluster nor DoorLock is present.
--- @param device st.matter.Device
--- @return number|nil
function schlage_utils.find_endpoint(device)
  local custom_eps = device:get_endpoints(constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID)
  if #custom_eps > 0 then
    return custom_eps[1]
  end
  local lock_eps = device:get_endpoints(DoorLock.ID)
  if #lock_eps > 0 then
    return lock_eps[1]
  end
  return nil
end

local function endpoint_or_warn(device, action)
  local ep = schlage_utils.find_endpoint(device)
  if ep == nil then
    device.log.warn(string.format("Schlage UWB endpoint not found; skipping %s", action))
  end
  return ep
end

--- @param device st.matter.Device
function schlage_utils.read_field_of_view(device)
  local ep = endpoint_or_warn(device, "Field of View read")
  if ep == nil then return end
  device.log.info(string.format("Reading Schlage UWB Field of View (Cluster: 0x%08X, Attr: 0x%04X, EP: %d)",
    constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_FIELD_OF_VIEW_ID, ep))
  device:send(cluster_base.read(device, ep, constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_FIELD_OF_VIEW_ID, nil))
end

--- @param device st.matter.Device
--- @param raw_value number
--- @return boolean true when the write was sent
function schlage_utils.write_field_of_view(device, raw_value)
  local ep = endpoint_or_warn(device, "Field of View write")
  if ep == nil then return false end
  device.log.info(string.format("Writing Schlage UWB Field of View: %d (Cluster: 0x%08X, Attr: 0x%04X, EP: %d)",
    raw_value, constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_FIELD_OF_VIEW_ID, ep))
  local data = data_types.validate_or_build_type(raw_value, data_types.Uint8)
  device:send(cluster_base.write(device, ep, constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_FIELD_OF_VIEW_ID, nil, data))
  return true
end

--- @param device st.matter.Device
function schlage_utils.read_intent_mode(device)
  local ep = endpoint_or_warn(device, "Intent Mode read")
  if ep == nil then return end
  device.log.info(string.format("Reading Schlage UWB Intent Mode (Cluster: 0x%08X, Attr: 0x%04X, EP: %d)",
    constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_INTENT_MODE_ID, ep))
  device:send(cluster_base.read(device, ep, constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_INTENT_MODE_ID, nil))
end

--- @param device st.matter.Device
--- @param raw_value number
--- @return boolean true when the write was sent
function schlage_utils.write_intent_mode(device, raw_value)
  local ep = endpoint_or_warn(device, "Intent Mode write")
  if ep == nil then return false end
  device.log.info(string.format("Writing Schlage UWB Intent Mode: %d (Cluster: 0x%08X, Attr: 0x%04X, EP: %d)",
    raw_value, constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_INTENT_MODE_ID, ep))
  local data = data_types.validate_or_build_type(raw_value, data_types.Uint8)
  device:send(cluster_base.write(device, ep, constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID, constants.ATTR_INTENT_MODE_ID, nil, data))
  return true
end

function schlage_utils.emit_supported_values(device)
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

--- Emit supported UWB values and read both attributes.
function schlage_utils.sync_uwb_settings(device)
  schlage_utils.emit_supported_values(device)
  schlage_utils.read_field_of_view(device)
  schlage_utils.read_intent_mode(device)
end

return schlage_utils
