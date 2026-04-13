-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local common_utils = require "common-utils"
local embedded_cluster_utils = require "embedded-cluster-utils"
local version = require "version"

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

local SUPPORTED_DISHWASHER_MODES = "__supported_dishwasher_modes"


-- Lifecycle Handlers --
local function do_configure(driver, device)
  local tn_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER})
  local tl_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL})
  local profile_name = "dishwasher"
  if #tn_eps > 0 then
    profile_name = profile_name .. "-tn"
    common_utils.query_setpoint_limits(device)
  end
  if #tl_eps > 0 then
    profile_name = profile_name .. "-tl"
  end
  device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
  device:try_update_metadata({profile = profile_name})
end

-- Matter Handlers --
local function temperature_setpoint_attr_handler(driver, device, ib, response)
  common_utils.temperature_setpoint_attr_handler(device, ib, "dishwasher")
end

local function setpoint_limit_handler(limit_field)
  return function(driver, device, ib, response)
    common_utils.setpoint_limit_handler(device, ib, limit_field, "dishwasher")
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
  local accepted_command_list = {}
  for _, accepted_command in ipairs(ib.data.elements) do
    local accepted_command_id = accepted_command.value
    if OPERATIONAL_STATE_COMMAND_MAP[accepted_command_id] ~= nil then
      device.log.info(string.format("AcceptedCommand: %s => %s", accepted_command_id, OPERATIONAL_STATE_COMMAND_MAP[accepted_command_id]))
      table.insert(accepted_command_list, OPERATIONAL_STATE_COMMAND_MAP[accepted_command_id])
    end
  end
  local event = capabilities.operationalState.supportedCommands(accepted_command_list, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function operational_state_attr_handler(driver, device, ib, response)
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
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local supportedDishwasherModes =device:get_field(SUPPORTED_DISHWASHER_MODES)
  for i, mode in ipairs(supportedDishwasherModes) do
    if cmd.args.mode == mode then
      device:send(clusters.DishwasherMode.commands.ChangeToMode(device, endpoint_id, i - 1))
      return
    end
  end
end

local function handle_temperature_setpoint(driver, device, cmd)
  common_utils.handle_temperature_setpoint(device, cmd, "dishwasher")
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
    doConfigure = do_configure
  },
  matter_handlers = {
    attr = {
      [clusters.TemperatureControl.ID] = {
        [clusters.TemperatureControl.attributes.TemperatureSetpoint.ID] = temperature_setpoint_attr_handler,
        [clusters.TemperatureControl.attributes.MinTemperature.ID] = setpoint_limit_handler(common_utils.setpoint_limit_device_field.MIN_TEMP),
        [clusters.TemperatureControl.attributes.MaxTemperature.ID] = setpoint_limit_handler(common_utils.setpoint_limit_device_field.MAX_TEMP)
      },
      [clusters.DishwasherMode.ID] = {
        [clusters.DishwasherMode.attributes.SupportedModes.ID] = dishwasher_supported_modes_attr_handler,
        [clusters.DishwasherMode.attributes.CurrentMode.ID] = dishwasher_mode_attr_handler
      },
      [clusters.DishwasherAlarm.ID] = {
        [clusters.DishwasherAlarm.attributes.State.ID] = dishwasher_alarm_attr_handler
      },
      [clusters.OperationalState.ID] = {
        [clusters.OperationalState.attributes.AcceptedCommandList.ID] = operational_state_accepted_command_list_attr_handler,
        [clusters.OperationalState.attributes.OperationalState.ID] = operational_state_attr_handler,
        [clusters.OperationalState.attributes.OperationalError.ID] = operational_error_attr_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_dishwasher_mode
    },
    [capabilities.temperatureSetpoint.ID] = {
      [capabilities.temperatureSetpoint.commands.setTemperatureSetpoint.NAME] = handle_temperature_setpoint
    },
    [capabilities.operationalState.ID] = {
      [capabilities.operationalState.commands.start.NAME] = handle_operational_state_start,
      [capabilities.operationalState.commands.stop.NAME] = handle_operational_state_stop,
      [capabilities.operationalState.commands.pause.NAME] = handle_operational_state_pause,
      [capabilities.operationalState.commands.resume.NAME] = handle_operational_state_resume
    }
  },
  can_handle = require("matter-dishwasher.can_handle"),
}

return matter_dishwasher_handler
