-- Copyright 2023 SmartThings
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
local clusters = require "st.matter.clusters"
local utils = require "st.utils"

local log = require "log"

-- Include driver-side definitions when lua libs api version is < 10
local version = require "version"
if version.api < 10 then
  clusters.RvcCleanMode = require "RvcCleanMode"
  clusters.RvcOperationalState = require "RvcOperationalState"
  clusters.RvcRunMode = require "RvcRunMode"
  clusters.OperationalState = require "OperationalState"
end

-- State Machine Rules 1. RVC Run Mode - Mode Change Restrictions
-- Attempting to switch the RVC Run Mode from a mode without the Idle mode tag to another non-Idle mode SHALL NOT be
-- allowed and the ChangeToModeResponse command SHALL have the StatusCode field set to the InvalidInMode value in that
-- case.
-- State Machine Rules 2. RVC Clean Mode - Mode Change Restrictions
-- This cluster SHALL NOT permit changing its mode while the RVC Run Mode cluster’s CurrentMode attribute is set to a
-- mode without the Idle mode tag. The ChangeToModeResponse command SHALL have the StatusCode field set to the
-- InvalidInMode value if this restriction prevents a mode change.
local DEFAULT_MODE = 0
local RVC_RUN_MODE_SUPPORTED_MODES = "__rvc_run_mode_supported_modes"
local RVC_CLEAN_MODE_SUPPORTED_MODES = "__rvc_clean_mode_supported_modes"

local function device_init(driver, device)
  device:subscribe()
end

-- Helper functions --
local function set_field_mode_tags_of_supported_mode(device, field_prefix, index, mode_tags)
  local field = string.format("%s_mode_tags_%d", field_prefix, index)
  local mode_tags_of_supported_modes = {}
  for _, mode_tag in ipairs(mode_tags.elements) do
    table.insert(mode_tags_of_supported_modes, mode_tag.elements.value.value)
  end
  device:set_field(field, mode_tags_of_supported_modes, { persist = true })
end

local function get_field_mode_tags_of_supported_mode(device, field_prefix, index)
  local field = string.format("%s_mode_tags_%d", field_prefix, index)
  return device:get_field(field)
end

local function set_field_supported_modes(device, field_prefix, supported_modes)
  local labels_field = string.format("%s_labels", field_prefix)
  local labels_of_supported_modes = {}
  device.log.info_with({hub_logs = true}, string.format("Supported modes: %s", utils.stringify_table(supported_modes)))
  for i, mode in ipairs(supported_modes) do
    if version.api < 10 then
      clusters.RvcRunMode.types.ModeOptionStruct:augment_type(mode)
    end
    table.insert(labels_of_supported_modes, mode.elements.label.value)
    set_field_mode_tags_of_supported_mode(device, field_prefix, i, mode.elements.mode_tags)
  end
  device:set_field(labels_field, labels_of_supported_modes, { persist = true })
end

local function set_field_supported_modes_from_response(device, field_prefix, cluster_id, attribute_id, response)
  for _, rb in ipairs(response.info_blocks) do
    if rb.info_block.attribute_id == attribute_id and
      rb.info_block.cluster_id == cluster_id and
      rb.info_block.data.elements ~= nil then
      set_field_supported_modes(device, field_prefix, rb.info_block.data.elements)
      break
    end
  end
end

local function get_field_labels_of_supported_modes(device, field_prefix)
  local field = string.format("%s_labels", field_prefix)
  return device:get_field(field)
end

local function get_labels_of_supported_modes(device, field_prefix, cluster_id, attribute_id, response)
  local supported_modes = get_field_labels_of_supported_modes(device, field_prefix)
  if supported_modes ~= nil then
    return supported_modes
  end

  set_field_supported_modes_from_response(device,
    field_prefix,
    cluster_id,
    attribute_id,
    response)
  return get_field_labels_of_supported_modes(device, field_prefix)
end

local function is_idle_mode(device, field_prefix, index, idle_mode_tag)
  local mode_tags = get_field_mode_tags_of_supported_mode(device, field_prefix, index)
  for _, mode_tag in ipairs(mode_tags) do
    if mode_tag == idle_mode_tag then
      return true
    end
  end
  return false
end

local function get_labels_of_supported_modes_filter_by_current_mode(device, field_prefix, idle_mode_tag, current_mode)
  local labels = get_field_labels_of_supported_modes(device, field_prefix)
  local is_idle_current_mode = false
  for i, label in ipairs(labels) do
    if label == current_mode then
      is_idle_current_mode = is_idle_mode(device, field_prefix, i, idle_mode_tag)
      break
    end
  end

  if is_idle_current_mode then
    return labels
  end

  local filtered_labels = {}
  table.insert(filtered_labels, current_mode)
  for i, label in ipairs(labels) do
    if is_idle_mode(device, field_prefix, i, idle_mode_tag) then
      table.insert(filtered_labels, label)
    end
  end
  return filtered_labels
end

-- Matter Handlers --
local function rvc_run_mode_supported_mode_attr_handler(driver, device, ib, response)
  set_field_supported_modes(device, RVC_RUN_MODE_SUPPORTED_MODES, ib.data.elements)

  -- State Machine Rules 1. RVC Run Mode - Mode Change Restrictions
  local current_mode = device:get_latest_state(
    "runMode",
    capabilities.mode.ID,
    capabilities.mode.mode.NAME
  ) or DEFAULT_MODE
  for _, rb in ipairs(response.info_blocks) do
    if rb.info_block.attribute_id == clusters.RvcRunMode.ID and
      rb.info_block.cluster_id == clusters.RvcRunMode.attributes.CurrentMode.ID and
      rb.info_block.data.value ~= nil then
      current_mode = rb.info_block.data.value
      break
    end
  end
  local labels_of_supported_arguments = get_labels_of_supported_modes_filter_by_current_mode(device,
    RVC_RUN_MODE_SUPPORTED_MODES,
    clusters.RvcRunMode.types.ModeTag.IDLE,
    current_mode
  )
  local labels_of_supported_modes = get_field_labels_of_supported_modes(device, RVC_RUN_MODE_SUPPORTED_MODES)
  local component = device.profile.components["runMode"]
  local event = capabilities.mode.supportedArguments(labels_of_supported_arguments, {visibility = {displayed = false}})
  device:emit_component_event(component, event)
  event = capabilities.mode.supportedModes(labels_of_supported_modes, {visibility = {displayed = false}})
  device:emit_component_event(component, event)
end

local function rvc_run_mode_current_mode_attr_handler(driver, device, ib, response)
  device.log.info_with({ hub_logs = true },
    string.format("rvc_run_mode_current_mode_attr_handler currentMode: %s", ib.data.value))

  local current_mode = ib.data.value
  local labels_of_supported_modes = get_labels_of_supported_modes(device,
    RVC_RUN_MODE_SUPPORTED_MODES,
    clusters.RvcRunMode.ID,
    clusters.RvcRunMode.attributes.SupportedModes.ID,
    response)
  for i, mode in ipairs(labels_of_supported_modes) do
    if i - 1 == current_mode then
      local component = device.profile.components["runMode"]
      device:emit_component_event(component, capabilities.mode.mode(mode))

      -- State Machine Rules 1. RVC Run Mode - Mode Change Restrictions
      local filtered_labels = get_labels_of_supported_modes_filter_by_current_mode(device,
        RVC_RUN_MODE_SUPPORTED_MODES,
        clusters.RvcRunMode.types.ModeTag.IDLE,
        mode
      )
      local event = capabilities.mode.supportedModes(filtered_labels, {visibility = {displayed = false}})
      device:emit_component_event(component, event)

      -- State Machine Rules 2. RVC Clean Mode - Mode Change Restrictions
      local is_idle = is_idle_mode(device, RVC_RUN_MODE_SUPPORTED_MODES, i, clusters.RvcRunMode.types.ModeTag.IDLE)
      local component = device.profile.components["cleanMode"]
      if is_idle then
        local labels_of_rvc_clean_mode = get_labels_of_supported_modes(device,
          RVC_CLEAN_MODE_SUPPORTED_MODES,
          clusters.RvcCleanMode.ID,
          clusters.RvcCleanMode.attributes.SupportedModes.ID,
          response)
        local event = capabilities.mode.supportedModes(labels_of_rvc_clean_mode, {visibility = {displayed = false}})
        device:emit_component_event(component, event)
      else
        local event = capabilities.mode.supportedModes({}, {visibility = {displayed = false}})
        device:emit_component_event(component, event)
      end
      break
    end
  end
end

local function rvc_clean_mode_supported_mode_attr_handler(driver, device, ib, response)
  set_field_supported_modes(device, RVC_CLEAN_MODE_SUPPORTED_MODES, ib.data.elements)
  local labels_of_supported_modes = get_field_labels_of_supported_modes(device, RVC_CLEAN_MODE_SUPPORTED_MODES)

  local component = device.profile.components["cleanMode"]
  local event = capabilities.mode.supportedArguments(labels_of_supported_modes, {visibility = {displayed = false}})
  device:emit_component_event(component, event)
  event = capabilities.mode.supportedModes(labels_of_supported_modes, {visibility = {displayed = false}})
  device:emit_component_event(component, event)
end

local function rvc_clean_mode_current_mode_attr_handler(driver, device, ib, response)
  device.log.info_with({ hub_logs = true },
    string.format("rvc_clean_mode_current_mode_attr_handler currentMode: %s", ib.data.value))

  local currentMode = ib.data.value
  local labels_of_supported_modes = get_labels_of_supported_modes(device,
    RVC_CLEAN_MODE_SUPPORTED_MODES,
    clusters.RvcCleanMode.ID,
    clusters.RvcCleanMode.attributes.SupportedModes.ID,
    response)
  for i, mode in ipairs(labels_of_supported_modes) do
    if i - 1 == currentMode then
      local component = device.profile.components["cleanMode"]
      device:emit_component_event(component, capabilities.mode.mode(mode))
      break
    end
  end
end

local function rvc_operational_state_attr_handler(driver, device, ib, response)
  device.log.info_with({ hub_logs = true },
    string.format("rvc_operational_state_attr_handler operationalState: %s", ib.data.value))

  if ib.data.value == clusters.OperationalState.types.OperationalStateEnum.STOPPED then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.stopped())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.RUNNING then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.running())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.PAUSED then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.paused())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.ERROR then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.error())
  elseif ib.data.value == clusters.RvcOperationalState.types.OperationalStateEnum.SEEKING_CHARGER then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.seekingCharger())
  elseif ib.data.value == clusters.RvcOperationalState.types.OperationalStateEnum.CHARGING then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.charging())
  elseif ib.data.value == clusters.RvcOperationalState.types.OperationalStateEnum.DOCKED then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.docked())
  end
end

local function rvc_operational_error_attr_handler(driver, device, ib, response)
  if version.api < 10 then
    clusters.OperationalState.types.ErrorStateStruct:augment_type(ib.data)
  end
  device.log.info_with({ hub_logs = true },
    string.format("rvc_operational_error_attr_handler errorStateID: %s", ib.data.elements.error_state_id.value))

  local operationalError = ib.data.elements.error_state_id.value
  if operationalError == clusters.OperationalState.types.ErrorStateEnum.UNABLE_TO_START_OR_RESUME then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.unableToStartOrResume())
  elseif operationalError == clusters.OperationalState.types.ErrorStateEnum.UNABLE_TO_COMPLETE_OPERATION then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.unableToCompleteOperation())
  elseif operationalError == clusters.OperationalState.types.ErrorStateEnum.COMMAND_INVALID_IN_STATE then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.commandInvalidInState())
  elseif operationalError == clusters.RvcOperationalState.types.ErrorStateEnum.FAILED_TO_FIND_CHARGING_DOCK then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.failedToFindChargingDock())
  elseif operationalError == clusters.RvcOperationalState.types.ErrorStateEnum.STUCK then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.stuck())
  elseif operationalError == clusters.RvcOperationalState.types.ErrorStateEnum.DUST_BIN_MISSING then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.dustBinMissing())
  elseif operationalError == clusters.RvcOperationalState.types.ErrorStateEnum.DUST_BIN_FULL then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.dustBinFull())
  elseif operationalError == clusters.RvcOperationalState.types.ErrorStateEnum.WATER_TANK_EMPTY then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.waterTankEmpty())
  elseif operationalError == clusters.RvcOperationalState.types.ErrorStateEnum.WATER_TANK_MISSING then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.waterTankMissing())
  elseif operationalError == clusters.RvcOperationalState.types.ErrorStateEnum.WATER_TANK_LID_OPEN then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.waterTankLidOpen())
  elseif operationalError == clusters.RvcOperationalState.types.ErrorStateEnum.MOP_CLEANING_PAD_MISSING then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerOperatingState.operatingState.mopCleaningPadMissing())
  end
end

-- Capability Handlers --
local function handle_robot_cleaner_mode(driver, device, cmd)
  device.log.info_with({ hub_logs = true },
    string.format("handle_robot_cleaner_mode component: %s, mode: %s", cmd.component, cmd.args.mode))

  local endpoint_id = device:component_to_endpoint(cmd.component)
  if cmd.component == "runMode" then
    local supported_modes = get_field_labels_of_supported_modes(device, RVC_RUN_MODE_SUPPORTED_MODES) or {}
    for i, mode in ipairs(supported_modes) do
      if cmd.args.mode == mode then
        device:send(clusters.RvcRunMode.commands.ChangeToMode(device, endpoint_id, i - 1))
        return
      end
    end
  elseif cmd.component == "cleanMode" then
    local supported_modes = get_field_labels_of_supported_modes(device, RVC_CLEAN_MODE_SUPPORTED_MODES) or {}
    for i, mode in ipairs(supported_modes) do
      if cmd.args.mode == mode then
        device:send(clusters.RvcCleanMode.commands.ChangeToMode(device, endpoint_id, i - 1))
        return
      end
    end
  end
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.RvcRunMode.ID] = {
        [clusters.RvcRunMode.attributes.SupportedModes.ID] = rvc_run_mode_supported_mode_attr_handler,
        [clusters.RvcRunMode.attributes.CurrentMode.ID] = rvc_run_mode_current_mode_attr_handler,
      },
      [clusters.RvcCleanMode.ID] = {
        [clusters.RvcCleanMode.attributes.SupportedModes.ID] = rvc_clean_mode_supported_mode_attr_handler,
        [clusters.RvcCleanMode.attributes.CurrentMode.ID] = rvc_clean_mode_current_mode_attr_handler,
      },
      [clusters.RvcOperationalState.ID] = {
        [clusters.RvcOperationalState.attributes.OperationalState.ID] = rvc_operational_state_attr_handler,
        [clusters.RvcOperationalState.attributes.OperationalError.ID] = rvc_operational_error_attr_handler,
      },
    }
  },
  subscribed_attributes = {
    [capabilities.mode.ID] = {
      clusters.RvcRunMode.attributes.SupportedModes,
      clusters.RvcRunMode.attributes.CurrentMode,
      clusters.RvcCleanMode.attributes.SupportedModes,
      clusters.RvcCleanMode.attributes.CurrentMode,
    },
    [capabilities.robotCleanerOperatingState.ID] = {
      clusters.RvcOperationalState.attributes.OperationalState,
      clusters.RvcOperationalState.attributes.OperationalError,
    },
  },
  capability_handlers = {
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_robot_cleaner_mode,
    },
  },
}

local matter_driver = MatterDriver("matter-rvc", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
