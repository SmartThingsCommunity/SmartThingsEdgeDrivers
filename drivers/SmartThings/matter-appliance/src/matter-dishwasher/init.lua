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

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "embedded-cluster-utils"
local log = require "log"
local utils = require "st.utils"
local version = require "version"

local DISHWASHER_DEVICE_TYPE_ID = 0x0075

if version.api < 10 then
  clusters.DishwasherAlarm = require "DishwasherAlarm"
  clusters.DishwasherMode = require "DishwasherMode"
  clusters.OperationalState = require "OperationalState"
  clusters.TemperatureControl = require "TemperatureControl"
end

local OPERATIONAL_STATE_COMMAND_MAP = {
  [clusters.OperationalState.commands.Pause.ID] = "pause",
  [clusters.OperationalState.commands.Stop.ID] = "stop",
  [clusters.OperationalState.commands.Start.ID] = "start",
  [clusters.OperationalState.commands.Resume.ID] = "resume",
}

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
local SUPPORTED_TEMPERATURE_LEVELS = "__supported_temperature_levels"
local SUPPORTED_DISHWASHER_MODES = "__supported_dishwasher_modes"

-- This is a work around to handle when units for temperatureSetpoint is changed for the App.
-- When units are switched, we will never know the units of the received command value as the arguments don't contain the unit.
-- So to handle this we assume the following ranges considering usual dishwasher temperatures:
--   1. if the received setpoint command value is in range 33 ~ 90, it is inferred as *C
--   2. if the received setpoint command value is in range 91.4 ~ 194, it is inferred as *F
local DISHWASHER_MAX_TEMP_IN_C = 90.0
local DISHWASHER_MIN_TEMP_IN_C = 33.0

local setpoint_limit_device_field = {
  MIN_TEMP = "MIN_TEMP",
  MAX_TEMP = "MAX_TEMP",
}

local function endpoint_to_component(device, ep)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  for component, endpoint in pairs(map) do
    if endpoint == ep then
      return component
    end
  end
  return "main"
end

local function component_to_endpoint(device, component)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  if map[component] then
    return map[component]
  end
  return device.MATTER_DEFAULT_ENDPOINT
end

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

-- Lifecycle Handlers --
local function device_init(driver, device)
  device:subscribe()
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

-- Matter Handlers --
local function selected_temperature_level_attr_handler(driver, device, ib, response)
  local tl_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL})
  if #tl_eps == 0 then
    device.log.warn_with({ hub_logs = true }, string.format("Device does not support TEMPERATURE_LEVEL feature"))
    return
  end
  device.log.info_with({ hub_logs = true },
    string.format("selected_temperature_level_attr_handler: %s", ib.data.value))

  local supportedTemperatureLevels = device:get_field(SUPPORTED_TEMPERATURE_LEVELS)
  local temperatureLevel = ib.data.value
  for i, tempLevel in ipairs(supportedTemperatureLevels) do
    if i - 1 == temperatureLevel then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureLevel.temperatureLevel(tempLevel))
      break
    end
  end
end

local function supported_temperature_levels_attr_handler(driver, device, ib, response)
  local tl_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL})
  if #tl_eps == 0 then
    device.log.warn_with({ hub_logs = true }, string.format("Device does not support TEMPERATURE_LEVEL feature"))
    return
  end
  device.log.info_with({ hub_logs = true },
    string.format("supported_temperature_levels_attr_handler: %s", ib.data.elements))

  local supportedTemperatureLevels = {}
  for _, tempLevel in ipairs(ib.data.elements) do
    table.insert(supportedTemperatureLevels, tempLevel.value)
  end
  device:set_field(SUPPORTED_TEMPERATURE_LEVELS, supportedTemperatureLevels, {persist = true})
  local event = capabilities.temperatureLevel.supportedTemperatureLevels(supportedTemperatureLevels, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function temperature_setpoint_attr_handler(driver, device, ib, response)
  local tn_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID,
    { feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER })
  if #tn_eps == 0 then
    device.log.warn(string.format("Device does not support TEMPERATURE_NUMBER feature"))
    return
  end
  device.log.info(string.format("temperature_setpoint_attr_handler: %d", ib.data.value))

  local min_field = string.format("%s-%d", setpoint_limit_device_field.MIN_TEMP, ib.endpoint_id)
  local max_field = string.format("%s-%d", setpoint_limit_device_field.MAX_TEMP, ib.endpoint_id)
  local min = device:get_field(min_field) or DISHWASHER_MIN_TEMP_IN_C
  local max = device:get_field(max_field) or DISHWASHER_MAX_TEMP_IN_C
  local temp = ib.data.value / 100.0
  local unit = "C"
  local range = {
    minimum = min,
    maximum = max,
    step = 0.1
  }

  -- Only emit the capability for RPC version >= 5, since unit conversion for
  -- range capabilities is only supported in that case.
  if version.rpc >= 5 then
    device:emit_event_for_endpoint(ib.endpoint_id,
      capabilities.temperatureSetpoint.temperatureSetpointRange({value = range, unit = unit}, {visibility = {displayed = false}}))
  end

  device:emit_event_for_endpoint(ib.endpoint_id,
    capabilities.temperatureSetpoint.temperatureSetpoint({value = temp, unit = unit}))
end

local function setpoint_limit_handler(limit_field)
  return function(driver, device, ib, response)
    local tn_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID,
      { feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER })
    if #tn_eps == 0 then
      device.log.warn(string.format("Device does not support TEMPERATURE_NUMBER feature"))
      return
    end
    local field = string.format("%s-%d", limit_field, ib.endpoint_id)
    local val = ib.data.value / 100.0

    val = utils.clamp_value(val, DISHWASHER_MIN_TEMP_IN_C, DISHWASHER_MAX_TEMP_IN_C)

    log.info("Setting " .. field .. " to " .. string.format("%s", val))
    device:set_field(field, val, { persist = true })
  end
end

local function dishwasher_supported_modes_attr_handler(driver, device, ib, response)
  local supportedDishwasherModes = {}
  for _, mode in ipairs(ib.data.elements) do
    if version.api < 10 then
      clusters.DishwasherMode.types.ModeOptionStruct:augment_type(mode)
    end
    table.insert(supportedDishwasherModes, mode.elements.label.value)
  end
  device:set_field(SUPPORTED_DISHWASHER_MODES, supportedDishwasherModes, { persist = true })
  local event = capabilities.mode.supportedModes(supportedDishwasherModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
  event = capabilities.mode.supportedArguments(supportedDishwasherModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function dishwasher_mode_attr_handler(driver, device, ib, response)
  device.log.info_with({ hub_logs = true },
    string.format("dishwasher_mode_attr_handler mode: %s", ib.data.value))

  local supportedDishwasherModes = device:get_field(SUPPORTED_DISHWASHER_MODES)
  local currentMode = ib.data.value
  for i, mode in ipairs(supportedDishwasherModes) do
    if i - 1 == currentMode then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.mode(mode))
      break
    end
  end
end

local function dishwasher_alarm_attr_handler(driver, device, ib, response)
  device.log.info_with({ hub_logs = true },
    string.format("dishwasher_alarm_attr_handler state: %s", ib.data.value))

  local isWaterFlowRateAlarm = false
  local isContactSensorAlarm = false
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
    isContactSensorAlarm = true
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
  if not isContactSensorAlarm then
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
  device.log.info_with({ hub_logs = true },
    string.format("operational_state_accepted_command_list_attr_handler: %s", ib.data.elements))

  local accepted_command_list = {}
  for _, accepted_command in ipairs(ib.data.elements) do
    local accepted_command_id = accepted_command.value
    if OPERATIONAL_STATE_COMMAND_MAP[accepted_command_id] ~= nil then
      device.log.info_with({ hub_logs = true }, string.format("AcceptedCommand: %s => %s", accepted_command_id, OPERATIONAL_STATE_COMMAND_MAP[accepted_command_id]))
      table.insert(accepted_command_list, OPERATIONAL_STATE_COMMAND_MAP[accepted_command_id])
    end
  end
  local event = capabilities.operationalState.supportedCommands(accepted_command_list, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function operational_state_attr_handler(driver, device, ib, response)
  device.log.info_with({ hub_logs = true },
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
  if version.api < 10 then
    clusters.OperationalState.types.ErrorStateStruct:augment_type(ib.data)
  end
  device.log.info_with({ hub_logs = true },
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
  device.log.info_with({ hub_logs = true },
    string.format("handle_dishwasher_mode mode: %s", cmd.args.mode))

  local endpoint_id = device:component_to_endpoint(cmd.component)
  local supportedDishwasherModes =device:get_field(SUPPORTED_DISHWASHER_MODES)
  for i, mode in ipairs(supportedDishwasherModes) do
    if cmd.args.mode == mode then
      device:send(clusters.DishwasherMode.commands.ChangeToMode(device, endpoint_id, i - 1))
      return
    end
  end
end

local function handle_temperature_level(driver, device, cmd)
  device.log.info_with({ hub_logs = true },
    string.format("handle_temperature_level: %s", cmd.args.temperatureLevel))

  local endpoint_id = device:component_to_endpoint(cmd.component)
  local supportedTemperatureLevels =device:get_field(SUPPORTED_TEMPERATURE_LEVELS)
  for i, tempLevel in ipairs(supportedTemperatureLevels) do
    if cmd.args.temperatureLevel == tempLevel then
      device:send(clusters.TemperatureControl.commands.SetTemperature(device, endpoint_id, nil, i - 1))
      return
    end
  end
end

local function handle_temperature_setpoint(driver, device, cmd)
  local tn_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID,
    { feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER })
  if #tn_eps == 0 then
    device.log.warn(string.format("Device does not support TEMPERATURE_NUMBER feature"))
    return
  end
  device.log.info(string.format("handle_temperature_setpoint: %s", cmd.args.setpoint))

  local value = cmd.args.setpoint
  local _, temp_setpoint = device:get_latest_state(
    cmd.component, capabilities.temperatureSetpoint.ID,
    capabilities.temperatureSetpoint.temperatureSetpoint.NAME,
    0, { value = 0, unit = "C" }
  )
  local ep = component_to_endpoint(device, cmd.component)
  local min_field = string.format("%s-%d", setpoint_limit_device_field.MIN_TEMP, ep)
  local max_field = string.format("%s-%d", setpoint_limit_device_field.MAX_TEMP, ep)
  local min = device:get_field(min_field) or DISHWASHER_MIN_TEMP_IN_C
  local max = device:get_field(max_field) or DISHWASHER_MAX_TEMP_IN_C

  if value > DISHWASHER_MAX_TEMP_IN_C then
    value = utils.f_to_c(value)
  end
  if value < min or value > max then
    log.warn(string.format(
      "Invalid setpoint (%s) outside the min (%s) and the max (%s)",
      value, min, max
    ))
    device:emit_event_for_endpoint(ep, capabilities.temperatureSetpoint.temperatureSetpoint(temp_setpoint))
    return
  end

  ep = component_to_endpoint(device, cmd.component)
  device:send(clusters.TemperatureControl.commands.SetTemperature(device, ep, utils.round(value * 100), nil))
end

local function handle_operational_state_start(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.OperationalState.server.commands.Start(device, endpoint_id))
  device:send(clusters.OperationalState.attributes.OperationalState:read(device, endpoint_id))
  device:send(clusters.OperationalState.attributes.OperationalError:read(device, endpoint_id))
end

local function handle_operational_state_stop(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.OperationalState.server.commands.Stop(device, endpoint_id))
  device:send(clusters.OperationalState.attributes.OperationalState:read(device, endpoint_id))
  device:send(clusters.OperationalState.attributes.OperationalError:read(device, endpoint_id))
end

local function handle_operational_state_resume(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.OperationalState.server.commands.Resume(device, endpoint_id))
  device:send(clusters.OperationalState.attributes.OperationalState:read(device, endpoint_id))
  device:send(clusters.OperationalState.attributes.OperationalError:read(device, endpoint_id))
end

local function handle_operational_state_pause(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.OperationalState.server.commands.Pause(device, endpoint_id))
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
        [clusters.TemperatureControl.attributes.TemperatureSetpoint.ID] = temperature_setpoint_attr_handler,
        [clusters.TemperatureControl.attributes.MinTemperature.ID] = setpoint_limit_handler(setpoint_limit_device_field.MIN_TEMP),
        [clusters.TemperatureControl.attributes.MaxTemperature.ID] = setpoint_limit_handler(setpoint_limit_device_field.MAX_TEMP),
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
    [capabilities.temperatureSetpoint.ID] = {
      [capabilities.temperatureSetpoint.commands.setTemperatureSetpoint.NAME] = handle_temperature_setpoint,
    },
    [capabilities.operationalState.ID] = {
      [capabilities.operationalState.commands.start.NAME] = handle_operational_state_start,
      [capabilities.operationalState.commands.stop.NAME] = handle_operational_state_stop,
      [capabilities.operationalState.commands.pause.NAME] = handle_operational_state_pause,
      [capabilities.operationalState.commands.resume.NAME] = handle_operational_state_resume,
    },
  },
  can_handle = is_matter_dishwasher,
}

return matter_dishwasher_handler
