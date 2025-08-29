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

local embedded_cluster_utils = require "embedded_cluster_utils"

-- Include driver-side definitions when lua libs api version is < 10
local version = require "version"
if version.api < 10 then
  clusters.RvcCleanMode = require "RvcCleanMode"
  clusters.RvcOperationalState = require "RvcOperationalState"
  clusters.RvcRunMode = require "RvcRunMode"
  clusters.OperationalState = require "OperationalState"
end

if version.api < 13 then
  clusters.ServiceArea = require "ServiceArea"
  clusters.Global = require "Global"
end

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
local RUN_MODE_SUPPORTED_MODES = "__run_mode_supported_modes"
local CLEAN_MODE_SUPPORTED_MODES = "__clean_mode_supported_modes"
local OPERATING_STATE_SUPPORTED_COMMANDS = "__operating_state_supported_commands"

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
  },
  [capabilities.serviceArea.ID] = {
    clusters.ServiceArea.attributes.SupportedAreas,
    clusters.ServiceArea.attributes.SelectedAreas
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
    ["main"] = run_mode_eps[1],
    ["runMode"] = run_mode_eps[1],
    ["cleanMode"] = clean_mode_eps[1]
  }
  device:set_field(COMPONENT_TO_ENDPOINT_MAP, component_to_endpoint_map, {persist = true})
end

local function device_init(driver, device)
  device:subscribe()
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local function do_configure(driver, device)
  local clean_mode_eps = device:get_endpoints(clusters.RvcCleanMode.ID) or {}
  local service_area_eps = embedded_cluster_utils.get_endpoints(device, clusters.ServiceArea.ID) or {}

  local profile_name = "rvc"
  if #clean_mode_eps > 0 then
    profile_name = profile_name .. "-clean-mode"
  end
  if #service_area_eps > 0 then
    profile_name = profile_name .. "-service-area"
  end

  device.log.info_with({hub_logs = true}, string.format("Updating device profile to %s.", profile_name))
  device:try_update_metadata({profile = profile_name})
  device:send(clusters.RvcOperationalState.attributes.AcceptedCommandList:read())
end

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    device:subscribe()
  end
end

-- Helper functions --
local function supports_rvc_operational_state(device, command_name)
  local supported_op_commands = device:get_field(OPERATING_STATE_SUPPORTED_COMMANDS) or {}
  for _, cmd in ipairs(supported_op_commands) do
    if cmd == command_name then
      return true
    end
  end
  return false
end

local function can_send_state_command(device, command_name, current_state, current_tag)
  device.log.info(string.format("can_send_state_command: %s, %s, %s", command_name, current_state, current_tag))
  if current_state == "Error" then
    return false
  end

  local set_mode = capabilities.mode.commands.setMode.NAME
  local cap_op_cmds = capabilities.robotCleanerOperatingState.commands
  local cap_op_enum = capabilities.robotCleanerOperatingState.operatingState
  if command_name ~= set_mode and supports_rvc_operational_state(device, command_name) == false then
    return false
  end

  if command_name == cap_op_cmds.goHome.NAME then
    if current_state ~= cap_op_enum.charging.NAME and current_state ~= cap_op_enum.docked.NAME then
      return true
    end
  elseif command_name == cap_op_cmds.pause.NAME then
    if current_tag == clusters.RvcRunMode.types.ModeTag.IDLE then
      if current_state == cap_op_enum.seekingCharger.NAME then
        return true
      end
    else
      if current_state == cap_op_enum.running.NAME or current_state == cap_op_enum.seekingCharger.NAME then
        return true
      end
    end
  elseif command_name == cap_op_cmds.start.NAME then
    if current_tag ~= clusters.RvcRunMode.types.ModeTag.IDLE then
      if current_state == cap_op_enum.paused.NAME or
         current_state == cap_op_enum.docked.NAME or
         current_state == cap_op_enum.charging.NAME then
        return true
      end
    end
  elseif command_name == set_mode then
    if current_tag == clusters.RvcRunMode.types.ModeTag.IDLE then
      if current_state == cap_op_enum.stopped.NAME or current_state == cap_op_enum.paused.NAME or
         current_state == cap_op_enum.docked.NAME or current_state == cap_op_enum.charging.NAME then
          return true
      end
    end
  end
  return false
end

local function update_supported_arguments(device, current_run_mode, current_state)
  device.log.info(string.format("update_supported_arguments: %s, %s", current_run_mode, current_state))
  if current_run_mode == nil or current_state == nil then
    return
  end

  if current_state == "Error" then
    -- Set Supported Operating State Commands to empty
    local event = capabilities.robotCleanerOperatingState.supportedOperatingStateCommands(
      {}, {visibility = {displayed = false}}
    )
    device:emit_component_event(device.profile.components["main"], event)
    -- Set runMode to empty
    event = capabilities.mode.supportedArguments({}, {visibility = {displayed = false}})
    device:emit_component_event(device.profile.components["runMode"], event)
    -- Set cleanMode to empty
    local component = device.profile.components["cleanMode"]
    if component ~= nil then
      device:emit_component_event(component, event)
    end
    return
  end

  -- Get the tag of the current run mode
  local current_tag = 0xFFFF
  local supported_run_modes = device:get_field(RUN_MODE_SUPPORTED_MODES) or {}
  for _, mode in ipairs(supported_run_modes) do
    if mode.label == current_run_mode then
      current_tag = mode.tag
      break
    end
  end
  if current_tag == 0xFFFF then
    device.log.error(string.format("Unsupported mode: %s", current_run_mode))
    return
  end

  -- Set Supported Operating State Commands
  local cap_op_cmds = capabilities.robotCleanerOperatingState.commands
  local cap_op_enum = capabilities.robotCleanerOperatingState.operatingState
  local supported_op_commands = {}

  if can_send_state_command(device, cap_op_cmds.goHome.NAME, current_state, nil) == true then
    table.insert(supported_op_commands, cap_op_cmds.goHome.NAME)
  end
  if can_send_state_command(device, cap_op_cmds.pause.NAME, current_state, current_tag) == true then
    table.insert(supported_op_commands, cap_op_cmds.pause.NAME)
  elseif can_send_state_command(device, cap_op_cmds.start.NAME, current_state, current_tag) == true or
         can_send_state_command(device, capabilities.mode.commands.setMode.NAME, current_state, current_tag) == true then
    table.insert(supported_op_commands, cap_op_cmds.start.NAME)
  end
  local event = capabilities.robotCleanerOperatingState.supportedOperatingStateCommands(
    supported_op_commands, {visibility = {displayed = false}}
  )
  device:emit_component_event(device.profile.components["main"], event)

  -- Check whether non-idle mode can be selected or not
  local can_be_non_idle = false
  if current_tag == clusters.RvcRunMode.types.ModeTag.IDLE and
    (current_state == cap_op_enum.stopped.NAME or current_state == cap_op_enum.paused.NAME or
     current_state == cap_op_enum.docked.NAME or current_state == cap_op_enum.charging.NAME) then
      can_be_non_idle = true
  end

  -- Set supported run arguments
  local supported_arguments = {} -- For generic plugin
  for _, mode in ipairs(supported_run_modes) do
    if mode.tag == clusters.RvcRunMode.types.ModeTag.IDLE or can_be_non_idle == true then
      table.insert(supported_arguments, mode.label)
    end
  end

  -- Send event to set supported run arguments
  local component = device.profile.components["runMode"]
  local event = capabilities.mode.supportedArguments(supported_arguments, {visibility = {displayed = false}})
  device:emit_component_event(component, event)

  -- Set supported clean arguments
  local supported_clean_modes = device:get_field(CLEAN_MODE_SUPPORTED_MODES) or {}
  supported_arguments = {}
  for _, mode in ipairs(supported_clean_modes) do
    table.insert(supported_arguments, mode.label)
  end

  -- Send event to set supported clean modes
  local component = device.profile.components["cleanMode"]
  if component ~= nil then
    local event = capabilities.mode.supportedArguments(supported_arguments, {visibility = {displayed = false}})
    device:emit_component_event(component, event)
  end
end

-- Matter Handlers --
local function run_mode_supported_mode_handler(driver, device, ib, response)
  local supported_modes = {}
  local supported_modes_id_tag = {}
  for _, mode in ipairs(ib.data.elements) do
    if version.api < 10 then
      clusters.RvcRunMode.types.ModeOptionStruct:augment_type(mode)
    end
    local tag = 0xFFFF
    for _, t in ipairs(mode.elements.mode_tags.elements) do
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
    if tag ~= 0xFFFF then
      table.insert(supported_modes, mode.elements.label.value)
      table.insert(supported_modes_id_tag, { label = mode.elements.label.value, id = mode.elements.mode.value, tag = tag })
    end
  end
  device:set_field(RUN_MODE_SUPPORTED_MODES, supported_modes_id_tag, { persist = true })

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
  local current_state = device:get_latest_state(
    "main",
    capabilities.robotCleanerOperatingState.ID,
    capabilities.robotCleanerOperatingState.operatingState.NAME
  )
  update_supported_arguments(device, current_run_mode, current_state)
end

local function run_mode_current_mode_handler(driver, device, ib, response)
  device.log.info(string.format("run_mode_current_mode_handler currentMode: %s", ib.data.value))

  -- Get label of current mode
  local mode_id = ib.data.value
  local supported_run_mode = device:get_field(RUN_MODE_SUPPORTED_MODES) or {}
  local current_run_mode = nil
  for _, mode in ipairs(supported_run_mode) do
    if mode.id == mode_id then
      current_run_mode = mode.label
    end
  end
  if current_run_mode == nil then
    return
  end

  -- Set current mode
  local component = device.profile.components["runMode"]
  device:emit_component_event(component, capabilities.mode.mode(current_run_mode))

  -- Update supported mode
  local current_state = device:get_latest_state(
    "main",
    capabilities.robotCleanerOperatingState.ID,
    capabilities.robotCleanerOperatingState.operatingState.NAME
  )
  update_supported_arguments(device, current_run_mode, current_state)
end

local function clean_mode_supported_mode_handler(driver, device, ib, response)
  device.log.info("clean_mode_supported_mode_handler")
  local supported_modes = {}
  local supported_modes_id = {}
  for _, mode in ipairs(ib.data.elements) do
    if version.api < 10 then
      clusters.RvcRunMode.types.ModeOptionStruct:augment_type(mode)
    end
    table.insert(supported_modes, mode.elements.label.value)
    table.insert(supported_modes_id, { label = mode.elements.label.value, id = mode.elements.mode.value })
  end
  device:set_field(CLEAN_MODE_SUPPORTED_MODES, supported_modes_id, { persist = true })

  local component = device.profile.components["cleanMode"]
  local event = capabilities.mode.supportedModes(supported_modes, {visibility = {displayed = false}})
  device:emit_component_event(component, event)
  event = capabilities.mode.supportedArguments(supported_modes, {visibility = {displayed = false}})
  device:emit_component_event(component, event)
end

local function clean_mode_current_mode_handler(driver, device, ib, response)
  device.log.info(string.format("clean_mode_current_mode_handler currentMode: %s", ib.data.value))
  local mode_id = ib.data.value
  local supported_clean_mode = device:get_field(CLEAN_MODE_SUPPORTED_MODES) or {}
  for _, mode in ipairs(supported_clean_mode) do
    if mode.id == mode_id then
      local component = device.profile.components["cleanMode"]
      device:emit_component_event(component, capabilities.mode.mode(mode.label))
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

local function handle_rvc_operational_state_accepted_command_list(driver, device, ib, response)
  device.log.info("handle_rvc_operational_state_accepted_command_list")
  local cap_op_cmds = capabilities.robotCleanerOperatingState.commands
  local OP_COMMAND_MAP = {
    [clusters.RvcOperationalState.commands.Pause.ID] = cap_op_cmds.pause,
    [clusters.RvcOperationalState.commands.Resume.ID] = cap_op_cmds.start,
    [clusters.RvcOperationalState.commands.GoHome.ID] = cap_op_cmds.goHome
  }
  local supportedOperatingStateCommands = {}
  for _, attr in ipairs(ib.data.elements) do
    table.insert(supportedOperatingStateCommands, OP_COMMAND_MAP[attr.value].NAME)
  end
  device:set_field(OPERATING_STATE_SUPPORTED_COMMANDS, supportedOperatingStateCommands, { persist = true })

  -- Get current run mode, current tag, current operating state
  local current_run_mode = device:get_latest_state(
    "runMode",
    capabilities.mode.ID,
    capabilities.mode.mode.NAME
  )
  local current_tag = 0xFFFF
  local supported_run_modes = device:get_field(RUN_MODE_SUPPORTED_MODES) or {}
  for _, mode in ipairs(supported_run_modes) do
    if mode.label == current_run_mode then
      current_tag = mode.tag
      break
    end
  end
  local current_state = device:get_latest_state(
    "main",
    capabilities.robotCleanerOperatingState.ID,
    capabilities.robotCleanerOperatingState.operatingState.NAME
  )
  local cap_op_enum = capabilities.robotCleanerOperatingState.operatingState
  if current_state ~= cap_op_enum.stopped.NAME and current_state ~= cap_op_enum.running.NAME and
     current_state ~= cap_op_enum.paused.NAME and current_state ~= cap_op_enum.seekingCharger.NAME and
     current_state ~= cap_op_enum.charging.NAME and current_state ~= cap_op_enum.docked.NAME then
      current_state = "Error"
  end

  -- Set Supported Operating State Commands
  local cap_op_cmds = capabilities.robotCleanerOperatingState.commands
  local supported_op_commands = {}
  if can_send_state_command(device, cap_op_cmds.goHome.NAME, current_state, current_tag) == true then
    table.insert(supported_op_commands, cap_op_cmds.goHome.NAME)
  end
  if can_send_state_command(device, cap_op_cmds.pause.NAME, current_state, current_tag) == true then
    table.insert(supported_op_commands, cap_op_cmds.pause.NAME)
  elseif can_send_state_command(device, cap_op_cmds.start.NAME, current_state, current_tag) == true or
         can_send_state_command(device, capabilities.mode.commands.setMode.NAME, current_state, current_tag) == true then
    table.insert(supported_op_commands, cap_op_cmds.start.NAME)
  end
  local event = capabilities.robotCleanerOperatingState.supportedOperatingStateCommands(
    supported_op_commands, {visibility = {displayed = false}}
  )
  device:emit_component_event(device.profile.components["main"], event)
end

local function upper_to_camelcase(name)
  local name_camelcase = (string.lower(name)):gsub("_"," ")
  name_camelcase = name_camelcase:gsub("(%l)(%w*)",
    function(a, b)
      return string.upper(a) .. b
    end)
  return name_camelcase
end

local function rvc_service_area_supported_areas_handler(driver, device, ib, response)
  local supported_areas = {}
  for i, area in ipairs(ib.data.elements) do
    if version.api < 13 then
      clusters.ServiceArea.types.AreaStruct:augment_type(area)
      clusters.ServiceArea.types.AreaInfoStruct:augment_type(area.elements.area_info)
      if area.elements.area_info.elements.location_info.elements ~= nil then
        clusters.Global.types.LocationDescriptorStruct:augment_type(area.elements.area_info.elements.location_info)
      end
    end
    local area_id = area.elements.area_id.value
    local location_info = area.elements.area_info.elements.location_info.elements
    local landmark_info = area.elements.area_info.elements.landmark_info.elements
    local area_name = ""
    -- Set the area name based on available location information
    if location_info ~= nil then
      if location_info.location_name.value ~= "" then
        area_name = location_info.location_name.value
      elseif location_info.floor_number.value ~= nil and location_info.area_type.value ~= nil then
        area_name = location_info.floor_number.value .. "F " .. upper_to_camelcase(string.gsub(clusters.Global.types.AreaTypeTag.pretty_print(location_info.area_type),"AreaTypeTag: ",""))
      elseif location_info.floor_number.value ~= nil then
        area_name = location_info.floor_number.value .. "F"
      elseif location_info.area_type.value ~= nil then
        area_name = upper_to_camelcase(string.gsub(clusters.Global.types.AreaTypeTag.pretty_print(location_info.area_type),"AreaTypeTag: ",""))
      end
    end
    if area_name == "" then
      area_name = upper_to_camelcase(string.gsub(clusters.Global.types.LandmarkTag.pretty_print(landmark_info.landmark_tag),"LandmarkTag: ",""))
    end
    table.insert(supported_areas, {["areaId"] = area_id, ["areaName"] = area_name})
  end

  -- Update Supported Areas
  local component = device.profile.components["main"]
  local event = capabilities.serviceArea.supportedAreas(supported_areas, {visibility = {displayed = false}})
  device:emit_component_event(component, event)
end

-- In case selected area is not in supportedarea then should i add to supported area or remove from selectedarea
local function rvc_service_area_selected_areas_handler(driver, device, ib, response)
  local selected_areas = {}
  for i, areaId in ipairs(ib.data.elements) do
    table.insert(selected_areas, areaId.value)
  end

  local component = device.profile.components["main"]
  local event = capabilities.serviceArea.selectedAreas(selected_areas, {visibility = {displayed = false}})
  device:emit_component_event(component, event)
end

local function robot_cleaner_areas_selection_response_handler(driver, device, ib, response)
  local select_areas_response = ib.info_block.data
  if version.api < 13 then
    clusters.ServiceArea.client.commands.SelectAreasResponse:augment_type(select_areas_response)
  end
  local status = select_areas_response.elements.status
  local status_text = select_areas_response.elements.status_text
  if status.value == clusters.ServiceArea.types.SelectAreasStatus.SUCCESS then
    device.log.info(string.format("robot_cleaner_areas_selection_response_handler: %s, %s",status.pretty_print(status),status_text))
  else
    device.log.error(string.format("robot_cleaner_areas_selection_response_handler: %s, %s",status.pretty_print(status),status_text))
    local selectedAreas = device:get_latest_state("main", capabilities.serviceArea.ID, capabilities.serviceArea.selectedAreas.NAME)
    local component = device.profile.components["main"]
    local event = capabilities.serviceArea.selectedAreas(selectedAreas, {state_change = true})
    device:emit_component_event(component, event)
  end
end

-- Capability Handlers --
local function handle_robot_cleaner_operating_state_start(driver, device, cmd)
  device.log.info("handle_robot_cleaner_operating_state_start")
  local endpoint_id = device:component_to_endpoint(cmd.component)

  -- Get current run mode, current tag, current operating state
  local current_run_mode = device:get_latest_state(
    "runMode",
    capabilities.mode.ID,
    capabilities.mode.mode.NAME
  )
  local current_tag = 0xFFFF
  local supported_run_modes = device:get_field(RUN_MODE_SUPPORTED_MODES) or {}
  for _, mode in ipairs(supported_run_modes) do
    if mode.label == current_run_mode then
      current_tag = mode.tag
      break
    end
  end
  local current_state = device:get_latest_state(
    "main",
    capabilities.robotCleanerOperatingState.ID,
    capabilities.robotCleanerOperatingState.operatingState.NAME
  )
  local cap_op_enum = capabilities.robotCleanerOperatingState.operatingState
  if current_state ~= cap_op_enum.stopped.NAME and current_state ~= cap_op_enum.running.NAME and
     current_state ~= cap_op_enum.paused.NAME and current_state ~= cap_op_enum.seekingCharger.NAME and
     current_state ~= cap_op_enum.charging.NAME and current_state ~= cap_op_enum.docked.NAME then
      current_state = "Error"
  end

  local cap_op_cmds = capabilities.robotCleanerOperatingState.commands
  if can_send_state_command(device, cap_op_cmds.start.NAME, current_state, current_tag) == true then
    device:send(clusters.RvcOperationalState.commands.Resume(device, endpoint_id))
  elseif can_send_state_command(device, capabilities.mode.commands.setMode.NAME, current_state, current_tag) == true then
    for _, mode in ipairs(supported_run_modes) do
      endpoint_id = device:component_to_endpoint("runMode")
      if mode.tag == clusters.RvcRunMode.types.ModeTag.CLEANING then
        device:send(clusters.RvcRunMode.commands.ChangeToMode(device, endpoint_id, mode.id))
        return
      end
    end
  end
end

local function handle_robot_cleaner_operating_state_pause(driver, device, cmd)
  device.log.info("handle_robot_cleaner_operating_state_pause")
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.RvcOperationalState.commands.Pause(device, endpoint_id))
end

local function handle_robot_cleaner_operating_state_go_home(driver, device, cmd)
  device.log.info("handle_robot_cleaner_operating_state_go_home")
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.RvcOperationalState.commands.GoHome(device, endpoint_id))
end

local function handle_robot_cleaner_mode(driver, device, cmd)
  device.log.info(string.format("handle_robot_cleaner_mode component: %s, mode: %s", cmd.component, cmd.args.mode))

  local endpoint_id = device:component_to_endpoint(cmd.component)
  if cmd.component == "runMode" then
    local supported_modes = device:get_field(RUN_MODE_SUPPORTED_MODES) or {}
    for _, mode in ipairs(supported_modes) do
      if cmd.args.mode == mode.label then
        device.log.info(string.format("mode.label: %s, mode.id: %s", mode.label, mode.id))
        device:send(clusters.RvcRunMode.commands.ChangeToMode(device, endpoint_id, mode.id))
        return
      end
    end
  elseif cmd.component == "cleanMode" then
    local supported_modes = device:get_field(CLEAN_MODE_SUPPORTED_MODES) or {}
    for _, mode in ipairs(supported_modes) do
      if cmd.args.mode == mode.label then
        device.log.info(string.format("mode.label: %s, mode.id: %s", mode.label, mode.id))
        device:send(clusters.RvcCleanMode.commands.ChangeToMode(device, endpoint_id, mode.id))
        return
      end
    end
  end
end

local uint32_dt = require "st.matter.data_types.Uint32"
local function handle_robot_cleaner_areas_selection(driver, device, cmd)
  device.log.info(string.format("handle_robot_cleaner_areas_selection component: %s, serviceArea: %s", cmd.component, cmd.args.areas.value))

  local selectAreas = clusters.ServiceArea.commands.SelectAreas(nil,nil,{})
  for i, areaId in ipairs(cmd.args.areas) do
    table.insert(selectAreas, uint32_dt(areaId))
  end
  local endpoint_id = device:component_to_endpoint(cmd.component)
  if cmd.component == "main" then
    device:send(clusters.ServiceArea.commands.SelectAreas(device, endpoint_id, selectAreas))
  end
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
        [clusters.RvcOperationalState.attributes.AcceptedCommandList.ID] = handle_rvc_operational_state_accepted_command_list,
      },
      [clusters.ServiceArea.ID] = {
        [clusters.ServiceArea.attributes.SupportedAreas.ID] = rvc_service_area_supported_areas_handler,
        [clusters.ServiceArea.attributes.SelectedAreas.ID] = rvc_service_area_selected_areas_handler,
      }
    },
    cmd_response={
      [clusters.ServiceArea.ID] = {
        [clusters.ServiceArea.client.commands.SelectAreasResponse.ID] = robot_cleaner_areas_selection_response_handler,
      }
    }
  },
  subscribed_attributes = subscribed_attributes,
  capability_handlers = {
    [capabilities.robotCleanerOperatingState.ID] = {
      [capabilities.robotCleanerOperatingState.commands.start.NAME] = handle_robot_cleaner_operating_state_start,
      [capabilities.robotCleanerOperatingState.commands.pause.NAME] = handle_robot_cleaner_operating_state_pause,
      [capabilities.robotCleanerOperatingState.commands.goHome.NAME] = handle_robot_cleaner_operating_state_go_home,
    },
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_robot_cleaner_mode,
    },
    [capabilities.serviceArea.ID] = {
      [capabilities.serviceArea.commands.selectAreas.NAME] = handle_robot_cleaner_areas_selection,
    },
  },
}

local matter_driver = MatterDriver("matter-rvc", matter_rvc_driver)
matter_driver:run()
