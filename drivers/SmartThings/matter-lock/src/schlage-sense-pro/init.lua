-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Subdriver for Allegion / Schlage Sense Pro UWB Door Lock
---
--- Enables lockUwbApproachSettings and lockUwbModeSettings as optional capabilities
--- on the shared modular lock profiles, and maps those capabilities onto the
--- Matter manufacturer-specific cluster.

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local device_configuration = require "device_configuration"
local lock_utils = require "lock_utils"
local constants = require "schlage-sense-pro.constants"
local schlage_utils = require "schlage-sense-pro.schlage_utils"

local DoorLock = clusters.DoorLock
local lockUwbApproachSettings = constants.get_lock_uwb_approach_settings_capability()
local lockUwbModeSettings = constants.get_lock_uwb_mode_settings_capability()

device_configuration.register_optional_capabilities(function(device)
  local matched = require("schlage-sense-pro.can_handle")(nil, nil, device)
  if matched then
    return {
      constants.CAPABILITY_LOCK_UWB_APPROACH_SETTINGS,
      constants.CAPABILITY_LOCK_UWB_MODE_SETTINGS,
    }
  end
end)

local function uwb_capabilities_missing(device)
  return not device:supports_capability_by_id(constants.CAPABILITY_LOCK_UWB_APPROACH_SETTINGS)
    or not device:supports_capability_by_id(constants.CAPABILITY_LOCK_UWB_MODE_SETTINGS)
end

-------------------------------------------------------------------------------------
-- Matter Attribute Handlers (Device -> SmartThings Hub)
-------------------------------------------------------------------------------------

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
    if schlage_utils.write_field_of_view(device, raw_val) then
      device:emit_event(lockUwbApproachSettings.approachDirection(constants.RAW_TO_APPROACH_DIRECTION[raw_val]))
    end
  else
    device.log.error(string.format("Invalid approachDirection argument: %s", tostring(val)))
  end
end

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
    if schlage_utils.write_intent_mode(device, raw_val) then
      device:emit_event(lockUwbModeSettings.intentMode(constants.RAW_TO_INTENT_MODE[raw_val]))
    end
  else
    device.log.error(string.format("Invalid intentMode argument: %s", tostring(val)))
  end
end

local function handle_refresh(driver, device, command)
  device.log.info("Refreshing Schlage Sense Pro UWB and Lock State")
  device:send(DoorLock.attributes.LockState:read(device))
  device:set_field(lock_utils.BUSY_STATE, false, { persist = true })
  schlage_utils.read_field_of_view(device)
  schlage_utils.read_intent_mode(device)
end

-------------------------------------------------------------------------------------
-- Lifecycle Handlers
-------------------------------------------------------------------------------------

local function device_init(driver, device)
  device.log.info("Schlage Sense Pro UWB subdriver device_init")
  if driver.lifecycle_handlers and driver.lifecycle_handlers.init then
    driver.lifecycle_handlers.init(driver, device)
  end

  if uwb_capabilities_missing(device) then
    device.log.info("Enabling Schlage Sense Pro UWB capabilities on the modular lock profile")
    device_configuration.match_profile(driver, device, false)
    schlage_utils.sync_uwb_settings(device)
  end
end

local function do_configure(driver, device)
  device.log.info("Schlage Sense Pro UWB subdriver do_configure")
  if driver.lifecycle_handlers and driver.lifecycle_handlers.doConfigure then
    driver.lifecycle_handlers.doConfigure(driver, device)
  end
  schlage_utils.sync_uwb_settings(device)
end

local function driver_switched(driver, device)
  device.log.info("Schlage Sense Pro UWB subdriver driver_switched")
  if driver.lifecycle_handlers and driver.lifecycle_handlers.driverSwitched then
    driver.lifecycle_handlers.driverSwitched(driver, device)
  end
  schlage_utils.sync_uwb_settings(device)
end

local schlage_sense_pro_subdriver = {
  NAME = "schlage-sense-pro",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
    driverSwitched = driver_switched,
  },
  matter_handlers = {
    attr = {
      [constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID] = {
        [constants.ATTR_FIELD_OF_VIEW_ID] = field_of_view_attr_handler,
        [constants.ATTR_INTENT_MODE_ID] = intent_mode_attr_handler,
      },
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
