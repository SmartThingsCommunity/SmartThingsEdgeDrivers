-- Copyright 2024 SmartThings
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
local log = require "log"
local version = require "version"

if version.api < 10 then
  clusters.OperationalState = require "OperationalState"
end

if version.api < 11 then
  clusters.MicrowaveOvenControl = require "MicrowaveOvenControl"
  clusters.MicrowaveOvenMode = require "MicrowaveOvenMode"
end

local OPERATIONAL_STATE_COMMAND_MAP = {
  [clusters.OperationalState.commands.Pause.ID] = "pause",
  [clusters.OperationalState.commands.Stop.ID] = "stop",
  [clusters.OperationalState.commands.Start.ID] = "start",
  [clusters.OperationalState.commands.Resume.ID] = "resume",
}

local MICROWAVE_OVEN_DEVICE_TYPE_ID = 0x0079
local DEFAULT_COOKING_MODE = 0
local DEFAULT_COOKING_TIME = 30
local MICROWAVE_OVEN_SUPPORTED_MODES_KEY = "__microwave_oven_supported_modes__"

local function device_init(driver, device)
  device:subscribe()
  device:send(clusters.MicrowaveOvenControl.attributes.MaxCookTime:read(device, device.MATTER_DEFAULT_ENDPOINT))
end

local function is_matter_mircowave_oven(opts, driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == MICROWAVE_OVEN_DEVICE_TYPE_ID then
        return true
      end
    end
  end
  return false
end

local function get_last_set_cooking_parameters(device)
  local cookingTime = device:get_latest_state("main", capabilities.cookTime.ID, capabilities.cookTime.cookTime.NAME) or DEFAULT_COOKING_TIME
  local cookingMode = device:get_latest_state("main", capabilities.mode.ID, capabilities.mode.mode.ID)
  local cookingModeId = DEFAULT_COOKING_MODE
  local microwaveOvenModeSupportedModes = device:get_field(MICROWAVE_OVEN_SUPPORTED_MODES_KEY) or {}
  for i, mode in ipairs(microwaveOvenModeSupportedModes) do
    if cookingMode == mode then
      cookingModeId = i - 1
      break
    end
  end
  return cookingTime, cookingModeId
end

local function operational_state_accepted_command_list_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("operational_state_accepted_command_list_attr_handler: %s", ib.data.elements))

  local accepted_command_list = {}
  for _, accepted_command in ipairs(ib.data.elements) do
    local accepted_command_id = accepted_command.value
    if OPERATIONAL_STATE_COMMAND_MAP[accepted_command_id] then
      log.info_with({ hub_logs = true },
        string.format("AcceptedCommand: %s => %s", accepted_command_id,
          OPERATIONAL_STATE_COMMAND_MAP[accepted_command_id]))
      table.insert(accepted_command_list, OPERATIONAL_STATE_COMMAND_MAP[accepted_command_id])
    end
  end
  local event = capabilities.operationalState.supportedCommands(accepted_command_list, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function operational_state_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("operational_state_attr_handler operationalState: %s", ib.data.value))

  local supported_mode = {}
  if ib.data.value == clusters.OperationalState.types.OperationalStateEnum.STOPPED then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.operationalState.operationalState.stopped())
    supported_mode = device:get_field(MICROWAVE_OVEN_SUPPORTED_MODES_KEY)
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.RUNNING then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.operationalState.operationalState.running())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.PAUSED then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.operationalState.operationalState.paused())
  end
  local event = capabilities.mode.supportedModes(supported_mode, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(device.MATTER_DEFAULT_ENDPOINT, event)
  event = capabilities.mode.supportedArguments(supported_mode, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(device.MATTER_DEFAULT_ENDPOINT, event)
end

local function operational_error_attr_handler(driver, device, ib, response)
  if version.api < 10 then
    clusters.OperationalState.types.ErrorStateStruct:augment_type(ib.data)
  end
  log.info_with({ hub_logs = true },
    string.format("operational_error_attr_handler errorStateID: %s", ib.data.elements.error_state_id.value))
  local operationalError = ib.data.elements.error_state_id.value
  if operationalError == clusters.OperationalState.types.ErrorStateEnum.UNABLE_TO_START_OR_RESUME then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.operationalState.operationalState.unableToStartOrResume())
  elseif operationalError == clusters.OperationalState.types.ErrorStateEnum.UNABLE_TO_COMPLETE_OPERATION then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.operationalState.operationalState.unableToCompleteOperation())
  elseif operationalError == clusters.OperationalState.types.ErrorStateEnum.COMMAND_INVALID_IN_STATE then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.operationalState.operationalState.commandInvalidInCurrentState())
  end
  if operationalError ~= clusters.OperationalState.types.ErrorStateEnum.NO_ERROR then
    local event = capabilities.mode.supportedModes({}, {visibility = {displayed = false}})
    device:emit_event_for_endpoint(device.MATTER_DEFAULT_ENDPOINT, event)
    event = capabilities.mode.supportedArguments({}, {visibility = {displayed = false}})
    device:emit_event_for_endpoint(device.MATTER_DEFAULT_ENDPOINT, event)
  end
end

local function microwave_oven_supported_modes_handler(driver, device, ib, response)
  local microwaveOvenModeSupportedModes = {}
  for _, mode in ipairs(ib.data.elements) do
    if version.api < 11 then
      clusters.MicrowaveOvenMode.types.ModeOptionStruct:augment_type(mode)
    end
    log.info_with({hub_logs=true},"Inserting supported microwave mode:", mode.elements.label.value)
    table.insert(microwaveOvenModeSupportedModes, mode.elements.label.value)
  end
  local event = capabilities.mode.supportedModes(microwaveOvenModeSupportedModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(device.MATTER_DEFAULT_ENDPOINT, event)
  event = capabilities.mode.supportedArguments(microwaveOvenModeSupportedModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(device.MATTER_DEFAULT_ENDPOINT, event)
  device:set_field(MICROWAVE_OVEN_SUPPORTED_MODES_KEY, microwaveOvenModeSupportedModes)
end

local function microwave_oven_current_mode_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("microwave_oven_current_mode_handler currentMode: %s", ib.data.value))

  local currentMode = ib.data.value
  local microwaveOvenModeSupportedModes = device:get_field(MICROWAVE_OVEN_SUPPORTED_MODES_KEY) or {}

  if microwaveOvenModeSupportedModes[currentMode + 1] then
    local mode = microwaveOvenModeSupportedModes[currentMode + 1]
    device:emit_event_for_endpoint(device.MATTER_DEFAULT_ENDPOINT, capabilities.mode.mode(mode))
    return
  end
  log.warn(string.format("Microwave oven mode %s not found in supported microwave oven modes", currentMode))
end

local function microwave_oven_cook_time_handler(driver, device, ib, response)
  local cookingTime = (ib.data.value == 0) and DEFAULT_COOKING_TIME or ib.data.value
  device:emit_event_for_endpoint(device.MATTER_DEFAULT_ENDPOINT, capabilities.cookTime.cookTime(cookingTime))
end

local function microwave_oven_max_cook_time_handler(driver, device, ib, response)
  local cook_time_range = {
    minimum = 1,
    maximum = ib.data.value
  }
  local event = capabilities.cookTime.cookTimeRange(cook_time_range, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(device.MATTER_DEFAULT_ENDPOINT, event)
end

---------------------
--capability handlers
---------------------
local function update_device_state(device, endpoint)
  device:send(clusters.OperationalState.attributes.OperationalState:read(device, endpoint))
  device:send(clusters.OperationalState.attributes.OperationalError:read(device, endpoint))
end

local function handle_operational_state_start(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.OperationalState.server.commands.Start(device, endpoint_id))
  update_device_state(device, endpoint_id)
end

local function handle_operational_state_stop(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.OperationalState.server.commands.Stop(device, endpoint_id))
  update_device_state(device, endpoint_id)
end

local function handle_operational_state_resume(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.OperationalState.server.commands.Resume(device, endpoint_id))
  update_device_state(device, endpoint_id)
end

local function handle_operational_state_pause(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.OperationalState.server.commands.Pause(device, endpoint_id))
  update_device_state(device, endpoint_id)
end

local function handle_microwave_oven_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("microwave_oven_mode[%s] mode: %s", cmd.component, cmd.args.mode))
  local microwaveOvenModeSupportedModes = device:get_field(MICROWAVE_OVEN_SUPPORTED_MODES_KEY) or {}
  for i, mode in ipairs(microwaveOvenModeSupportedModes) do
    if cmd.args.mode == mode then
      local cookingTime, _ = get_last_set_cooking_parameters(device)
      device:send(clusters.MicrowaveOvenControl.commands.SetCookingParameters(device, device.MATTER_DEFAULT_ENDPOINT,
        i - 1,
        cookingTime))
      return
    end
  end
  log.warn(string.format("Microwave oven mode %s not found in supported modes", cmd.args.mode))
end

local function handle_set_cooking_time(driver, device, cmd)
  local cookingTime = cmd.args.time
  local _, mode_id = get_last_set_cooking_parameters(device)
  device:send(clusters.MicrowaveOvenControl.commands.SetCookingParameters(device, device.MATTER_DEFAULT_ENDPOINT, mode_id,
    cookingTime))
end

local matter_microwave_oven = {
  NAME = "matter-microwave-oven",
  lifecycle_handlers = {
    init = device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.OperationalState.ID] = {
        [clusters.OperationalState.attributes.AcceptedCommandList.ID] =
            operational_state_accepted_command_list_attr_handler,
        [clusters.OperationalState.attributes.OperationalState.ID] = operational_state_attr_handler,
        [clusters.OperationalState.attributes.OperationalError.ID] = operational_error_attr_handler,
      },
      [clusters.MicrowaveOvenMode.ID] = {
        [clusters.MicrowaveOvenMode.attributes.SupportedModes.ID] = microwave_oven_supported_modes_handler,
        [clusters.MicrowaveOvenMode.attributes.CurrentMode.ID] = microwave_oven_current_mode_handler,
      },
      [clusters.MicrowaveOvenControl.ID] = {
        [clusters.MicrowaveOvenControl.attributes.MaxCookTime.ID] = microwave_oven_max_cook_time_handler,
        [clusters.MicrowaveOvenControl.attributes.CookTime.ID] = microwave_oven_cook_time_handler,
      }
    },
  },
  capability_handlers = {
    [capabilities.operationalState.ID] = {
      [capabilities.operationalState.commands.start.NAME] = handle_operational_state_start,
      [capabilities.operationalState.commands.stop.NAME] = handle_operational_state_stop,
      [capabilities.operationalState.commands.pause.NAME] = handle_operational_state_pause,
      [capabilities.operationalState.commands.resume.NAME] = handle_operational_state_resume,
    },
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_microwave_oven_mode,
    },
    [capabilities.cookTime.ID] = {
      [capabilities.cookTime.commands.setCookTime.NAME] = handle_set_cooking_time,
    },
  },
  supported_capabilities = {
    capabilities.operationalState,
    capabilities.mode,
    capabilities.cookTime
  },
  can_handle = is_matter_mircowave_oven,
}

return matter_microwave_oven
