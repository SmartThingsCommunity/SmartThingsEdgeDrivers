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

local DISHWASHER_DEVICE_TYPE_ID = 0x0075

local OPERATIONAL_STATE_COMMAND_MAP = {
  [clusters.OperationalState.commands.Pause.ID] = "pause",
  [clusters.OperationalState.commands.Stop.ID] = "stop",
  [clusters.OperationalState.commands.Start.ID] = "start",
  [clusters.OperationalState.commands.Resume.ID] = "resume",
}

local supportedTemperatureLevels = {}
local dishwasherModeSupportedModes = {}

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
local function is_matter_dishwasher(opts, driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == DISHWASHER_DEVICE_TYPE_ID then
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
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureLevel.supportedTemperatureLevels(supportedTemperatureLevels))
end

local function dishwasher_supported_modes_attr_handler(driver, device, ib, response)
  dishwasherModeSupportedModes = {}
  for _, mode in ipairs(ib.data.elements) do
    table.insert(dishwasherModeSupportedModes, mode.elements.label.value)
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.supportedModes(dishwasherModeSupportedModes))
end

local function dishwasher_mode_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("dishwasher_mode_attr_handler currentMode: %s", ib.data.value))

  local currentMode = ib.data.value
  for i, mode in ipairs(dishwasherModeSupportedModes) do
    if i - 1 == currentMode then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.mode(mode))
      break
    end
  end
end

local function dishwasher_alarm_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("dishwasher_alarm_attr_handler state: %s", ib.data.value))

  local isWaterFlowRateAlarm = false
  local isContacSensorAlarm = false
  local isTemperatureAlarm = false
  local isWaterFlowVolumeAlarm = false

  local state = ib.data.value
  if state & clusters.DishwasherAlarm.types.AlarmMap.INFLOW_ERROR > 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.waterFlowAlarm.rateAlarm.alarm())
    isWaterFlowRateAlarm = true
  end
  if state & clusters.DishwasherAlarm.types.AlarmMap.DRAIN_ERROR > 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.waterFlowAlarm.rateAlarm.alarm())
    isWaterFlowRateAlarm = true
  end
  if state & clusters.DishwasherAlarm.types.AlarmMap.DOOR_ERROR > 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.contactSensor.contact.open())
    isContacSensorAlarm = true
  end
  if state & clusters.DishwasherAlarm.types.AlarmMap.TEMP_TOO_LOW > 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureAlarm.temperatureAlarm.freeze())
    isTemperatureAlarm = true
  end
  if state & clusters.DishwasherAlarm.types.AlarmMap.TEMP_TOO_HIGH > 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureAlarm.temperatureAlarm.heat())
    isTemperatureAlarm = true
  end
  if state & clusters.DishwasherAlarm.types.AlarmMap.WATER_LEVEL_ERROR > 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.waterFlowAlarm.volumeAlarm.alarm())
    isWaterFlowVolumeAlarm = true
  end

  if not isWaterFlowRateAlarm then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.waterFlowAlarm.rateAlarm.normal())
  end
  if not isContacSensorAlarm then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.contactSensor.contact.closed())
  end
  if not isTemperatureAlarm then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureAlarm.temperatureAlarm.cleared())
  end
  if not isWaterFlowVolumeAlarm then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.waterFlowAlarm.volumeAlarm.normal())
  end
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
local function handle_dishwasher_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("handle_dishwasher_mode mode: %s", cmd.args.mode))

  local ENDPOINT = 1
  for i, mode in ipairs(dishwasherModeSupportedModes) do
    if cmd.args.mode == mode then
      device:send(clusters.DishwasherMode.commands.ChangeToMode(device, ENDPOINT, i - 1))
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

local matter_dishwasher_handler = {
  NAME = "matter-dishwasher",
  lifecycle_handlers = {
    init = device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.TemperatureControl.ID] = {
        [clusters.TemperatureControl.attributes.SelectedTemperatureLevel.ID] = selected_temperature_level_attr_handler,
        [clusters.TemperatureControl.attributes.SupportedTemperatureLevels.ID] = supported_temperature_levels_attr_handler,
      },
      [clusters.DishwasherMode.ID] = {
        [clusters.DishwasherMode.attributes.SupportedModes.ID] = dishwasher_supported_modes_attr_handler,
        [clusters.DishwasherMode.attributes.CurrentMode.ID] = dishwasher_mode_attr_handler,
      },
      [clusters.DishwasherAlarm.ID] = {
        [clusters.DishwasherAlarm.attributes.State.ID] = dishwasher_alarm_attr_handler,
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
      [capabilities.mode.commands.setMode.NAME] = handle_dishwasher_mode,
    },
    [capabilities.temperatureLevel.ID] = {
      [capabilities.temperatureLevel.commands.setTemperatureLevel.NAME] = handle_temperature_level,
    },
    [capabilities.operationalState.ID] = {
      [capabilities.operationalState.commands.setOperationalState.NAME] = handle_set_operating_state,
    },
  },
  can_handle = is_matter_dishwasher,
}

return matter_dishwasher_handler
