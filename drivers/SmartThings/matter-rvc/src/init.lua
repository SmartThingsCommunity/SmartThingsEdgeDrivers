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

-- Include driver-side definitions when lua libs api version is < 10
local version = require "version"
if version.api < 10 then
  clusters.RvcCleanMode = require "RvcCleanMode"
  clusters.RvcOperationalState = require "RvcOperationalState"
  clusters.RvcRunMode = require "RvcRunMode"
  clusters.OperationalState = require "OperationalState"
end

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
local RUN_MODE_SUPPORTED_MODES = "__run_mode_supported_modes"
local CLEAN_MODE_SUPPORTED_MODES = "__clean_mode_supported_modes"

local subscribed_attributes = {
  [capabilities.mode.ID] = {
    clusters.RvcRunMode.attributes.SupportedModes,
    clusters.RvcRunMode.attributes.CurrentMode,
    clusters.RvcCleanMode.attributes.SupportedModes,
    clusters.RvcCleanMode.attributes.CurrentMode
  },
  [capabilities.robotCleanerOperatingState.ID] = {
    clusters.RvcOperationalState.attributes.OperationalState,
    clusters.RvcOperationalState.attributes.OperationalError
  }
}

local function component_to_endpoint(device, component)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  if map[component] then
    return map[component]
  else
    return device.MATTER_DEFAULT_ENDPOINT
  end
end

local function device_added(driver, device)
  local run_mode_eps = device:get_endpoints(clusters.RvcRunMode.ID) or {}
  local clean_mode_eps = device:get_endpoints(clusters.RvcCleanMode.ID) or {}
  local component_to_endpoint_map = {
    ["runMode"] = run_mode_eps[1],
    ["cleanMode"] = clean_mode_eps[1]
  }
  device:set_field(COMPONENT_TO_ENDPOINT_MAP, component_to_endpoint_map, {persist = true} )
end

local function device_init(driver, device)
  device:subscribe()
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local function do_configure(driver, device)
  local clean_mode_eps = device:get_endpoints(clusters.RvcCleanMode.ID)
  if #clean_mode_eps == 0 then
    local profile_name = "rvc"
    device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({profile = profile_name})
  end
end

local function info_changed(driver, device, event, args)
  for cap_id, attributes in pairs(subscribed_attributes) do
    if device:supports_capability_by_id(cap_id) then
      for _, attr in ipairs(attributes) do
        device:add_subscribed_attribute(attr)
      end
    end
  end
  device:subscribe()
end

-- Helper functions --
local function update_supported_arguments(device, current_run_mode, operating_state)
  device.log.info(string.format("update_supported_arguments: %s, %s", current_run_mode, operating_state))
  if current_run_mode == nil or operating_state == nil then
    return
  end

  -- Error state
  if operating_state == "Error" then
    -- Set runMode to empty
    local component = device.profile.components["runMode"]
    local event = capabilities.mode.supportedArguments({}, {visibility = {displayed = false}})
    device:emit_component_event(component, event)
    -- Set cleanMode to empty
    component = device.profile.components["cleanMode"]
    device:emit_component_event(component, event)
    return
  end

  -- Get the tag of the current run mode
  local current_tag = 0xFFFF
  local supported_run_modes = device:get_field(RUN_MODE_SUPPORTED_MODES) or {}
  for i, mode in ipairs(supported_run_modes) do
    if mode[1] == current_run_mode then
      current_tag = mode[2]
      break
    end
  end
  if current_tag == 0xFFFF then
    return
  end

  -- Check whether non-idle mode can be selected or not
  local op_state = capabilities.robotCleanerOperatingState.operatingState
  local can_be_selected_as_non_idle = 0
  if current_tag == clusters.RvcRunMode.types.ModeTag.IDLE and
    (operating_state == op_state.stopped.NAME or operating_state == op_state.paused.NAME or
     operating_state == op_state.docked.NAME or operating_state == op_state.charging.NAME) then
      can_be_selected_as_non_idle = 1
  end

  -- Set supported run arguments
  local supported_arguments = {} -- For generic plugin
  for i, mode in ipairs(supported_run_modes) do
    if mode[2] == clusters.RvcRunMode.types.ModeTag.IDLE or can_be_selected_as_non_idle == 1 then
      table.insert(supported_arguments, mode[1])
    end
  end

  -- Send event to set supported run arguments
  local component = device.profile.components["runMode"]
  local event = capabilities.mode.supportedArguments(supported_arguments, {visibility = {displayed = false}})
  device:emit_component_event(component, event)

  -- Set supported clean arguments
  local supported_clean_modes = device:get_field(CLEAN_MODE_SUPPORTED_MODES) or {}
  supported_arguments = {}
  for i, mode in ipairs(supported_clean_modes) do
    table.insert(supported_arguments, mode)
  end

  -- Send event to set supported clean modes
  local component = device.profile.components["cleanMode"]
  local event = capabilities.mode.supportedArguments(supported_arguments, {visibility = {displayed = false}})
  device:emit_component_event(component, event)
end

-- Matter Handlers --
local function run_mode_supported_mode_handler(driver, device, ib, response)
  local supported_modes = {}
  local supported_modes_with_tag = {}
  for i, mode in ipairs(ib.data.elements) do
    if version.api < 10 then
      clusters.RvcRunMode.types.ModeOptionStruct:augment_type(mode)
    end
    local tag = 0xFFFF
    for i, t in ipairs(mode.elements.mode_tags.elements) do
      if t.elements.value.value == clusters.RvcRunMode.types.ModeTag.IDLE then
        tag = clusters.RvcRunMode.types.ModeTag.IDLE
        break
      elseif t.elements.value.value == clusters.RvcRunMode.types.ModeTag.CLEANING then
        tag = clusters.RvcRunMode.types.ModeTag.CLEANING
        break
      elseif t.elements.value.value == clusters.RvcRunMode.types.ModeTag.MAPPING then
        tag = clusters.RvcRunMode.types.ModeTag.MAPPING
        break
      end
    end
    table.insert(supported_modes, mode.elements.label.value)
    table.insert(supported_modes_with_tag, {mode.elements.label.value, tag})
  end
  device:set_field(RUN_MODE_SUPPORTED_MODES, supported_modes_with_tag, { persist = true })

  -- Update Supported Modes
  local component = device.profile.components["runMode"]
  local event = capabilities.mode.supportedModes(supported_modes, {visibility = {displayed = false}})
  device:emit_component_event(component, event)

  -- Update Supported Arguments
  local current_run_mode = device:get_latest_state(
    "runMode",
    capabilities.mode.ID,
    capabilities.mode.mode.NAME
  )
  local operating_state = device:get_latest_state(
    "main",
    capabilities.robotCleanerOperatingState.ID,
    capabilities.robotCleanerOperatingState.operatingState.NAME
  )
  update_supported_arguments(device, current_run_mode, operating_state)
end

local function run_mode_current_mode_handler(driver, device, ib, response)
  device.log.info(string.format("run_mode_current_mode_handler currentMode: %s", ib.data.value))

  -- Get label of current mode
  local mode_index = ib.data.value
  local supported_run_mode = device:get_field(RUN_MODE_SUPPORTED_MODES) or {}
  local current_run_mode = nil
  for i, mode in ipairs(supported_run_mode) do
    if i - 1 == mode_index then
      current_run_mode = mode[1]
    end
  end
  if current_run_mode == nil then
    return
  end

  -- Set current mode
  local component = device.profile.components["runMode"]
  device:emit_component_event(component, capabilities.mode.mode(current_run_mode))

  -- Update supported mode
  local operating_state = device:get_latest_state(
    "main",
    capabilities.robotCleanerOperatingState.ID,
    capabilities.robotCleanerOperatingState.operatingState.NAME
  )
  update_supported_arguments(device, current_run_mode, operating_state)
end

local function clean_mode_supported_mode_handler(driver, device, ib, response)
  device.log.info(string.format("clean_mode_supported_mode_handler"))
  local supported_modes = {}
  for i, mode in ipairs(ib.data.elements) do
    if version.api < 10 then
      clusters.RvcRunMode.types.ModeOptionStruct:augment_type(mode)
    end
    table.insert(supported_modes, mode.elements.label.value)
  end
  device:set_field(CLEAN_MODE_SUPPORTED_MODES, supported_modes, { persist = true })

  local component = device.profile.components["cleanMode"]
  local event = capabilities.mode.supportedModes(supported_modes, {visibility = {displayed = false}})
  device:emit_component_event(component, event)
  event = capabilities.mode.supportedArguments(supported_modes, {visibility = {displayed = false}})
  device:emit_component_event(component, event)
end

local function clean_mode_current_mode_handler(driver, device, ib, response)
  device.log.info(string.format("clean_mode_current_mode_handler currentMode: %s", ib.data.value))
  local mode_index = ib.data.value
  local supported_clean_mode = device:get_field(CLEAN_MODE_SUPPORTED_MODES) or {}
  for i, mode in ipairs(supported_clean_mode) do
    if i - 1 == mode_index then
      local component = device.profile.components["cleanMode"]
      device:emit_component_event(component, capabilities.mode.mode(mode))
      break
    end
  end
end

local function rvc_operational_state_attr_handler(driver, device, ib, response)
  device.log.info(string.format("rvc_operational_state_attr_handler operationalState: %s", ib.data.value))
  local clus_op_enum = clusters.OperationalState.types.OperationalStateEnum
  local clus_rvc_op_enum = clusters.RvcOperationalState.types.OperationalStateEnum
  local cap_op_enum = capabilities.robotCleanerOperatingState.operatingState
  local OPERATING_STATE_MAP = {
    [clus_op_enum.STOPPED] = cap_op_enum.stopped,
    [clus_op_enum.RUNNING] = cap_op_enum.running,
    [clus_op_enum.PAUSED] = cap_op_enum.paused,
    [clus_rvc_op_enum.SEEKING_CHARGER] = cap_op_enum.seekingCharger,
    [clus_rvc_op_enum.CHARGING] = cap_op_enum.charging,
    [clus_rvc_op_enum.DOCKED] = cap_op_enum.docked
  }
  if ib.data.value ~= clus_op_enum.ERROR then
    device:emit_event_for_endpoint(ib.endpoint_id, OPERATING_STATE_MAP[ib.data.value]())
  end

  -- Supported Mode update
  local current_run_mode = device:get_latest_state(
    "runMode",
    capabilities.mode.ID,
    capabilities.mode.mode.NAME
  )
  if ib.data.value ~= clus_op_enum.ERROR then
    update_supported_arguments(device, current_run_mode, OPERATING_STATE_MAP[ib.data.value].NAME)
  else
    update_supported_arguments(device, current_run_mode, "Error")
  end
end

local function rvc_operational_error_attr_handler(driver, device, ib, response)
  if version.api < 10 then
    clusters.OperationalState.types.ErrorStateStruct:augment_type(ib.data)
  end

  device.log.info(string.format("rvc_operational_error_attr_handler errorStateID: %s", ib.data.elements.error_state_id.value))

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
  device.log.info(string.format("handle_robot_cleaner_mode component: %s, mode: %s", cmd.component, cmd.args.mode))

  local endpoint_id = device:component_to_endpoint(cmd.component)
  if cmd.component == "runMode" then
    local supported_modes = device:get_field(RUN_MODE_SUPPORTED_MODES) or {}
    for i, mode in ipairs(supported_modes) do
      if cmd.args.mode == mode[1] then
        device:send(clusters.RvcRunMode.commands.ChangeToMode(device, endpoint_id, i - 1))
        return
      end
    end
  elseif cmd.component == "cleanMode" then
    local supported_modes = device:get_field(CLEAN_MODE_SUPPORTED_MODES) or {}
    for i, mode in ipairs(supported_modes) do
      if cmd.args.mode == mode then
        device:send(clusters.RvcCleanMode.commands.ChangeToMode(device, endpoint_id, i - 1))
        return
      end
    end
  end
end

local function handle_refresh(driver, device, command)
  local req = clusters.RvcRunMode.attributes.CurrentMode:read(device)
  req:merge(clusters.RvcCleanMode.attributes.CurrentMode:read(device))
  req:merge(clusters.RvcOperationalState.attributes.OperationalState:read(device))
  device:send(req)
end

local matter_rvc_driver = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    infoChanged = info_changed,
  },
  matter_handlers = {
    attr = {
      [clusters.RvcRunMode.ID] = {
        [clusters.RvcRunMode.attributes.SupportedModes.ID] = run_mode_supported_mode_handler,
        [clusters.RvcRunMode.attributes.CurrentMode.ID] = run_mode_current_mode_handler,
      },
      [clusters.RvcCleanMode.ID] = {
        [clusters.RvcCleanMode.attributes.SupportedModes.ID] = clean_mode_supported_mode_handler,
        [clusters.RvcCleanMode.attributes.CurrentMode.ID] = clean_mode_current_mode_handler,
      },
      [clusters.RvcOperationalState.ID] = {
        [clusters.RvcOperationalState.attributes.OperationalState.ID] = rvc_operational_state_attr_handler,
        [clusters.RvcOperationalState.attributes.OperationalError.ID] = rvc_operational_error_attr_handler,
      },
    }
  },
  subscribed_attributes = subscribed_attributes,
  capability_handlers = {
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_robot_cleaner_mode,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = handle_refresh
    },
  },
}

local matter_driver = MatterDriver("matter-rvc", matter_rvc_driver)
matter_driver:run()
