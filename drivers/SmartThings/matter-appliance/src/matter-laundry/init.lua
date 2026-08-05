-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local common_utils = require "common-utils"
local embedded_cluster_utils = require "embedded-cluster-utils"
local log = require "log"
local version = require "version"

local LAUNDRY_WASHER_DEVICE_TYPE_ID = 0x0073
local LAUNDRY_DRYER_DEVICE_TYPE_ID = 0x007C

if version.api < 10 then
  clusters.LaundryWasherControls = require "LaundryWasherControls"
  clusters.LaundryWasherMode = require "LaundryWasherMode"
  clusters.OperationalState = require "OperationalState"
  clusters.TemperatureControl = require "TemperatureControl"
end

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

local LAUNDRY_DEVICE_TYPE_ID= "__laundry_device_type_id"
local SUPPORTED_LAUNDRY_WASHER_MODES = "__supported_laundry_washer_modes"
local SUPPORTED_LAUNDRY_WASHER_SPIN_SPEEDS = "__supported_laundry_spin_speeds"
local SUPPORTED_LAUNDRY_WASHER_RINSES = "__supported_laundry_washer_rinses"

-- Lifecycle Handlers --
local function do_configure(driver, device)
  local tn_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER})
  local tl_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL})
  local is_matter_laundry_device = require("matter-laundry.can_handle")
  local device_type, _ = is_matter_laundry_device({}, driver, device)
  local profile_name = "laundry"
  if (device_type == LAUNDRY_WASHER_DEVICE_TYPE_ID) then
    profile_name = profile_name.."-washer"
  else
    profile_name = profile_name.."-dryer"
  end
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

local function get_device_type(device)
  local laundry_device_type_id = device:get_field(LAUNDRY_DEVICE_TYPE_ID)
  return laundry_device_type_id == LAUNDRY_DRYER_DEVICE_TYPE_ID and "dryer" or "washer"
end

-- Matter Handlers --
local function temperature_setpoint_attr_handler(driver, device, ib, response)
  common_utils.temperature_setpoint_attr_handler(device, ib, get_device_type(device))
end

local function setpoint_limit_handler(limit_field)
  return function(driver, device, ib, response)
    common_utils.setpoint_limit_handler(device, ib, limit_field, get_device_type(device))
  end
end

local function laundry_washer_supported_modes_attr_handler(driver, device, ib, response)
  local supportedLaundryWasherModes = {}
  for _, mode in ipairs(ib.data.elements) do
    if version.api < 10 then
      clusters.LaundryWasherMode.types.ModeOptionStruct:augment_type(mode)
    end
    log.info(string.format("Inserting supported washer mode: %s", mode.elements.label.value))
    table.insert(supportedLaundryWasherModes, mode.elements.label.value)
  end
  local component = device.profile.components["main"]
  device:set_field(SUPPORTED_LAUNDRY_WASHER_MODES, supportedLaundryWasherModes, {persist = true})
  local event = capabilities.mode.supportedModes(supportedLaundryWasherModes, {visibility = {displayed = false}})
  device:emit_component_event(component, event)
  event = capabilities.mode.supportedArguments(supportedLaundryWasherModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function laundry_washer_mode_attr_handler(driver, device, ib, response)
  local supportedLaundryWasherModes = device:get_field(SUPPORTED_LAUNDRY_WASHER_MODES)
  local currentMode = ib.data.value
  for i, mode in ipairs(supportedLaundryWasherModes) do
    if i - 1 == currentMode then
      local component = device.profile.components["main"]
      device:emit_component_event(component, capabilities.mode.mode(mode))
      return
    end
  end
  log.warn(string.format("Washer mode %s not found in supported washer modes", currentMode))
end

local function laundry_washer_controls_spin_speeds_attr_handler(driver, device, ib, response)
  local supportedLaundryWasherSpinSpeeds = {}
  for _, spinSpeed in ipairs(ib.data.elements) do
    log.info(string.format("Inserting supported spin speed mode: %s", spinSpeed.value))
    table.insert(supportedLaundryWasherSpinSpeeds, spinSpeed.value)
  end
  device:set_field(SUPPORTED_LAUNDRY_WASHER_SPIN_SPEEDS, supportedLaundryWasherSpinSpeeds, {persist = true})
  local event = capabilities.laundryWasherSpinSpeed.supportedSpinSpeeds(supportedLaundryWasherSpinSpeeds, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function laundry_washer_controls_spin_speed_current_attr_handler(driver, device, ib, response)
  local supportedLaundryWasherSpinSpeeds = device:get_field(SUPPORTED_LAUNDRY_WASHER_SPIN_SPEEDS)
  local spinSpeedCurrent = ib.data.value
  for i, spinSpeed in ipairs(supportedLaundryWasherSpinSpeeds) do
    if i - 1 == spinSpeedCurrent then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.laundryWasherSpinSpeed.spinSpeed(spinSpeed))
      return
    end
  end
  log.warn(string.format("Spin speed %s not found in supported speed modes", spinSpeedCurrent))
end

local function laundry_washer_controls_number_of_rinses_attr_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib.endpoint_id, LAUNDRY_WASHER_RINSE_MODE_MAP[ib.data.value]())
end

local function laundry_washer_controls_supported_rinses_attr_handler(driver, device, ib, response)
  local supportedLaundryWasherRinses = {}
  for _, numberOfRinses in ipairs(ib.data.elements) do
    device.log.info(string.format("numberOfRinses: %s => %s", numberOfRinses.value, LAUNDRY_WASHER_RINSE_MODE_MAP[numberOfRinses.value].NAME))
    table.insert(supportedLaundryWasherRinses, LAUNDRY_WASHER_RINSE_MODE_MAP[numberOfRinses.value].NAME)
  end
  device:set_field(SUPPORTED_LAUNDRY_WASHER_RINSES, supportedLaundryWasherRinses, {persist = true})
  local event = capabilities.laundryWasherRinseMode.supportedRinseModes(supportedLaundryWasherRinses, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
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
local function handle_laundry_washer_mode(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local supportedLaundryWasherModes = device:get_field(SUPPORTED_LAUNDRY_WASHER_MODES)
  for i, mode in ipairs(supportedLaundryWasherModes) do
    if cmd.args.mode == mode then
      device:send(clusters.LaundryWasherMode.commands.ChangeToMode(device, endpoint_id, i - 1))
      return
    end
  end
end

local function handle_laundry_washer_spin_speed(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local supportedLaundryWasherSpinSpeeds = device:get_field(SUPPORTED_LAUNDRY_WASHER_SPIN_SPEEDS)
  for i, spinSpeed in ipairs(supportedLaundryWasherSpinSpeeds) do
    if cmd.args.spinSpeed == spinSpeed then
      device:send(clusters.LaundryWasherControls.attributes.SpinSpeedCurrent:write(device, endpoint_id, i - 1))
      return
    end
  end
end

local function handle_laundry_washer_rinse_mode(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  for clusterVal, capabilityVal in pairs(LAUNDRY_WASHER_RINSE_MODE_MAP) do
    if cmd.args.rinseMode == capabilityVal.NAME then
      device:send(clusters.LaundryWasherControls.attributes.NumberOfRinses:write(device, endpoint_id, clusterVal))
      break
    end
  end
end

local function handle_temperature_setpoint(driver, device, cmd)
  common_utils.handle_temperature_setpoint(device, cmd, get_device_type(device))
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

local matter_laundry_handler = {
  NAME = "matter-laundry",
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
      [clusters.LaundryWasherMode.ID] = {
        [clusters.LaundryWasherMode.attributes.SupportedModes.ID] = laundry_washer_supported_modes_attr_handler,
        [clusters.LaundryWasherMode.attributes.CurrentMode.ID] = laundry_washer_mode_attr_handler
      },
      [clusters.LaundryWasherControls.ID] = {
        [clusters.LaundryWasherControls.attributes.SpinSpeeds.ID] = laundry_washer_controls_spin_speeds_attr_handler,
        [clusters.LaundryWasherControls.attributes.SpinSpeedCurrent.ID] = laundry_washer_controls_spin_speed_current_attr_handler,
        [clusters.LaundryWasherControls.attributes.NumberOfRinses.ID] = laundry_washer_controls_number_of_rinses_attr_handler,
        [clusters.LaundryWasherControls.attributes.SupportedRinses.ID] = laundry_washer_controls_supported_rinses_attr_handler
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
      [capabilities.mode.commands.setMode.NAME] = handle_laundry_washer_mode
    },
    [capabilities.temperatureSetpoint.ID] = {
      [capabilities.temperatureSetpoint.commands.setTemperatureSetpoint.NAME] = handle_temperature_setpoint
    },
    [capabilities.laundryWasherSpinSpeed.ID] = {
      [capabilities.laundryWasherSpinSpeed.commands.setSpinSpeed.NAME] = handle_laundry_washer_spin_speed
    },
    [capabilities.laundryWasherRinseMode.ID] = {
      [capabilities.laundryWasherRinseMode.commands.setRinseMode.NAME] = handle_laundry_washer_rinse_mode
    },
    [capabilities.operationalState.ID] = {
      [capabilities.operationalState.commands.start.NAME] = handle_operational_state_start,
      [capabilities.operationalState.commands.stop.NAME] = handle_operational_state_stop,
      [capabilities.operationalState.commands.pause.NAME] = handle_operational_state_pause,
      [capabilities.operationalState.commands.resume.NAME] = handle_operational_state_resume
    }
  },
  can_handle = require("matter-laundry.can_handle"),
}

return matter_laundry_handler
