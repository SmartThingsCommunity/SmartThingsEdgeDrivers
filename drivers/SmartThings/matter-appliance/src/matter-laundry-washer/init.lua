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

local log = require "log"
local utils = require "st.utils"

local LAUNDRY_WASHER_DEVICE_TYPE_ID = 0x0073

local LAUNDRY_WASHER_RINSE_MODE_MAP = {
  [clusters.LaundryWasherControls.types.NumberOfRinsesEnum.NONE] = capabilities.laundryWasherRinseMode.rinseMode.none,
  [clusters.LaundryWasherControls.types.NumberOfRinsesEnum.NORMAL] = capabilities.laundryWasherRinseMode.rinseMode.normal,
  [clusters.LaundryWasherControls.types.NumberOfRinsesEnum.EXTRA] = capabilities.laundryWasherRinseMode.rinseMode.extra,
  [clusters.LaundryWasherControls.types.NumberOfRinsesEnum.MAX] = capabilities.laundryWasherRinseMode.rinseMode.max,
}
local OPERATIONAL_STATE_COMMAND_MAP = {
  [clusters.OperationalState.commands.Pause.ID] = "pause",
  [clusters.OperationalState.commands.Stop.ID] = "stop",
  [clusters.OperationalState.commands.Start.ID] = "start",
  [clusters.OperationalState.commands.Resume.ID] = "resume",
}

local supportedTemperatureLevels = {}
local laundryWasherModeSupportedModes = {}
local laundryWasherControlsSpinSpeeds = {}
local laundryWasherControlsSupportedRinses = {}

-- helper functions
local function key_exists(array, key)
  for k, _ in pairs(array) do
    if k == key then
      return true
    end
  end
  return false
end
--------------------------------------------------------------------------

local function device_init(driver, device)
  device:subscribe()
end

-- Matter Handlers --
local function is_matter_laundry_washer(opts, driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == LAUNDRY_WASHER_DEVICE_TYPE_ID then
        return true
      end
    end
  end
  return false
end

local function selected_temperature_level_attr_handler(driver, device, ib, response)
  local tl_eps = device:get_endpoints(clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL})
  if #tl_eps == 0 then
    log.warn_with({ hub_logs = true }, string.format("Device does not support TEMPERATURE_LEVEL feature"))
    return
  end
  log.info_with({ hub_logs = true },
    string.format("selected_temperature_level_attr_handler: %s", ib.data.value))

  local temperatureLevel = ib.data.value
  for i, tempLevel in ipairs(supportedTemperatureLevels) do
    if i - 1 == temperatureLevel then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureLevel.temperatureLevel(tempLevel))
      break
    end
  end
end

local function supported_temperature_levels_attr_handler(driver, device, ib, response)
  local tl_eps = device:get_endpoints(clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL})
  if #tl_eps == 0 then
    log.warn_with({ hub_logs = true }, string.format("Device does not support TEMPERATURE_LEVEL feature"))
    return
  end
  log.info_with({ hub_logs = true },
    string.format("supported_temperature_levels_attr_handler: %s", ib.data.elements))

  supportedTemperatureLevels = {}
  for _, tempLevel in ipairs(ib.data.elements) do
    table.insert(supportedTemperatureLevels, tempLevel.value)
  end
  local component = device.profile.components["temperatureLevel"]
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureLevel.supportedTemperatureLevels(supportedTemperatureLevels))
end

local function laundry_washer_supported_modes_attr_handler(driver, device, ib, response)
  laundryWasherModeSupportedModes = {}
  for _, mode in ipairs(ib.data.elements) do
    log.info(string.format("Inserting supported washer mode: %s", mode.elements.label.value))
    table.insert(laundryWasherModeSupportedModes, mode.elements.label.value)
  end
  -- TODO: Create laundryWasherSpinSpeed
  -- device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.supportedModes(laundryWasherModeSupportedModes))
  local component = device.profile.components["main"]
  device:emit_component_event(component, capabilities.mode.supportedModes(laundryWasherModeSupportedModes))
end

local function laundry_washer_mode_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("laundry_washer_mode_attr_handler currentMode: %s", ib.data.value))

  local currentMode = ib.data.value
  for i, mode in ipairs(laundryWasherModeSupportedModes) do
    if i - 1 == currentMode then
      -- TODO: Create laundryWasherSpinSpeed
      -- device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.mode(mode))
      local component = device.profile.components["main"]
      device:emit_component_event(component, capabilities.mode.mode(mode))
      return
    end
  end
  log.warn(string.format("Washer mode %s not found in supported washer modes", spinSpeed.value))
end

local function laundry_washer_controls_spin_speeds_attr_handler(driver, device, ib, response)
  laundryWasherControlsSpinSpeeds = {}
  for _, spinSpeed in ipairs(ib.data.elements) do
    log.info(string.format("Inserting supported spin speed mode: %s", spinSpeed.value))
    table.insert(laundryWasherControlsSpinSpeeds, spinSpeed.value)
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.laundryWasherSpinSpeed.supportedSpinSpeeds(laundryWasherControlsSpinSpeeds))
end

local function laundry_washer_controls_spin_speed_current_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("laundry_washer_controls_spin_speed_current_attr_handler spinSpeedCurrent: %s", ib.data.value))

  local spinSpeedCurrent = ib.data.value
  for i, spinSpeed in ipairs(laundryWasherControlsSpinSpeeds) do
    if i - 1 == spinSpeedCurrent then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.laundryWasherSpinSpeed.spinSpeed(spinSpeed))
      return
    end
  end
  log.warn(string.format("Spin speed %s not found in supported speed modes", spinSpeed.value))
end

local function laundry_washer_controls_number_of_rinses_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("laundry_washer_controls_number_of_rinses_attr_handler numberOfRinses: %s", ib.data.value))

  device:emit_event_for_endpoint(ib.endpoint_id, LAUNDRY_WASHER_RINSE_MODE_MAP[ib.data.value]())
end

local function laundry_washer_controls_supported_rinses_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("laundry_washer_controls_supported_rinses_attr_handler: %s", ib.data.elements))

  laundryWasherControlsSupportedRinses = {}
  for _, numberOfRinses in ipairs(ib.data.elements) do
    log.info_with({ hub_logs = true }, string.format("numberOfRinses: %s => %s", numberOfRinses.value, LAUNDRY_WASHER_RINSE_MODE_MAP[numberOfRinses.value].NAME))
    table.insert(laundryWasherControlsSupportedRinses, LAUNDRY_WASHER_RINSE_MODE_MAP[numberOfRinses.value].NAME)
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.laundryWasherRinseMode.supportedRinseModes(laundryWasherControlsSupportedRinses))
end

local function operational_state_accepted_command_list_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("operational_state_accepted_command_list_attr_handler: %s", ib.data.elements))

  local accepted_command_list = {}
  for _, accepted_command in ipairs(ib.data.elements) do
    local accepted_command_id = accepted_command.value
    if key_exists(OPERATIONAL_STATE_COMMAND_MAP, accepted_command_id) then
      log.info_with({ hub_logs = true }, string.format("AcceptedCommand: %s => %s", accepted_command_id, OPERATIONAL_STATE_COMMAND_MAP[accepted_command_id]))
      table.insert(accepted_command_list, OPERATIONAL_STATE_COMMAND_MAP[accepted_command_id])
    end
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.operationalState.supportedSelectableStates(accepted_command_list))
end

local function operational_state_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("operational_state_attr_handler operationalState: %s", ib.data.value))

  if ib.data.value == clusters.OperationalState.types.OperationalStateEnum.STOPPED then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.operationalState.operationalState.stopped())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.RUNNING then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.operationalState.operationalState.running())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.PAUSED then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.operationalState.operationalState.paused())
  end
end

local function operational_error_attr_handler(driver, device, ib, response)
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
end

-- Capability Handlers --
local function handle_laundry_washer_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("handle_laundry_washer_mode[%s] mode: %s", cmd.component, cmd.args.mode))

  local ENDPOINT = 1
  for i, mode in ipairs(laundryWasherModeSupportedModes) do
    if cmd.args.mode == mode then
      device:send(clusters.LaundryWasherMode.commands.ChangeToMode(device, ENDPOINT, i - 1))
      return
    end
  end
end

local function handle_temperature_level(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("handle_temperature_level: %s", cmd.args.temperatureLevel))

  local ENDPOINT = 1
  for i, tempLevel in ipairs(supportedTemperatureLevels) do
    if cmd.args.temperatureLevel == tempLevel then
      device:send(clusters.TemperatureControl.commands.SetTemperature(device, ENDPOINT, nil, i - 1))
      return
    end
  end
end

local function handle_laundry_washer_spin_speed(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("handle_laundry_washer_spin_speed spinSpeed: %s", cmd.args.spinSpeed))

  local ENDPOINT = 1
  for i, spinSpeed in ipairs(laundryWasherControlsSpinSpeeds) do
    if cmd.args.spinSpeed == spinSpeed then
      device:send(clusters.LaundryWasherControls.attributes.SpinSpeedCurrent:write(device, ENDPOINT, i - 1))
      return
    end
  end
end

local function handle_laundry_washer_rinse_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("handle_laundry_washer_rinse_mode rinseMode: %s", cmd.args.rinseMode))

  local ENDPOINT = 1
  for clusterVal, capabilityVal in pairs(LAUNDRY_WASHER_RINSE_MODE_MAP) do
    if cmd.args.rinseMode == capabilityVal.NAME then
      device:send(clusters.LaundryWasherControls.attributes.NumberOfRinses:write(device, ENDPOINT, clusterVal))
      break
    end
  end
end

local function handle_set_operating_state(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("handle_set_operating_state state: %s", cmd.args.operationalState))

  local endpoint_id = device:component_to_endpoint(cmd.component)
  local state = cmd.args.operationalState
  if state == "start" then
    device:send(clusters.OperationalState.server.commands.Start(device, endpoint_id))
  elseif state == "stop" then
    device:send(clusters.OperationalState.server.commands.Stop(device, endpoint_id))
  elseif state == "resume" then
    device:send(clusters.OperationalState.server.commands.Resume(device, endpoint_id))
  elseif state == "pause" then
    device:send(clusters.OperationalState.server.commands.Pause(device, endpoint_id))
  end
  device:send(clusters.OperationalState.attributes.OperationalState:read(device, endpoint_id))
  device:send(clusters.OperationalState.attributes.OperationalError:read(device, endpoint_id))
end

local matter_laundry_washer_handler = {
  NAME = "matter-laundry-washer",
  lifecycle_handlers = {
    init = device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.TemperatureControl.ID] = {
        [clusters.TemperatureControl.attributes.SelectedTemperatureLevel.ID] = selected_temperature_level_attr_handler,
        [clusters.TemperatureControl.attributes.SupportedTemperatureLevels.ID] = supported_temperature_levels_attr_handler,
      },
      [clusters.LaundryWasherMode.ID] = {
        [clusters.LaundryWasherMode.attributes.SupportedModes.ID] = laundry_washer_supported_modes_attr_handler,
        [clusters.LaundryWasherMode.attributes.CurrentMode.ID] = laundry_washer_mode_attr_handler,
      },
      [clusters.LaundryWasherControls.ID] = {
        [clusters.LaundryWasherControls.attributes.SpinSpeeds.ID] = laundry_washer_controls_spin_speeds_attr_handler,
        [clusters.LaundryWasherControls.attributes.SpinSpeedCurrent.ID] = laundry_washer_controls_spin_speed_current_attr_handler,
        [clusters.LaundryWasherControls.attributes.NumberOfRinses.ID] = laundry_washer_controls_number_of_rinses_attr_handler,
        [clusters.LaundryWasherControls.attributes.SupportedRinses.ID] = laundry_washer_controls_supported_rinses_attr_handler,
      },
      [clusters.OperationalState.ID] = {
        [clusters.OperationalState.attributes.AcceptedCommandList.ID] = operational_state_accepted_command_list_attr_handler,
        [clusters.OperationalState.attributes.OperationalState.ID] = operational_state_attr_handler,
        [clusters.OperationalState.attributes.OperationalError.ID] = operational_error_attr_handler,
      },
    }
  },
  capability_handlers = {
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_laundry_washer_mode,
    },
    [capabilities.temperatureLevel.ID] = {
      [capabilities.temperatureLevel.commands.setTemperatureLevel.NAME] = handle_temperature_level,
    },
    [capabilities.laundryWasherSpinSpeed.ID] = {
      [capabilities.laundryWasherSpinSpeed.commands.setSpinSpeed.NAME] = handle_laundry_washer_spin_speed,
    },
    [capabilities.laundryWasherRinseMode.ID] = {
      [capabilities.laundryWasherRinseMode.commands.setRinseMode.NAME] = handle_laundry_washer_rinse_mode,
    },
    [capabilities.operationalState.ID] = {
      [capabilities.operationalState.commands.setOperationalState.NAME] = handle_set_operating_state,
    },
  },
  can_handle = is_matter_laundry_washer,
}

return matter_laundry_washer_handler
