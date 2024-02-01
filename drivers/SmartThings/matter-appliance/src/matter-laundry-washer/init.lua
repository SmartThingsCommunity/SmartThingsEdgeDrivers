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

local applianceOperationalStateId = "spacewonder52282.applianceOperationalState"
local applianceOperationalState = capabilities[applianceOperationalStateId]
local supportedTemperatureLevels = {}
local laundryWasherModeSupportedModes = {}
local laundryWasherControlsSpinSpeeds = {}
local laundryWasherControlsSupportedRinses = {}

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

-- TODO Create temperatureLevel
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
      local component = device.profile.components["temperatureLevel"]
      device:emit_component_event(component, capabilities.mode.mode(tempLevel))
      break
    end
  end
end

-- TODO Create temperatureLevel
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
  device:emit_component_event(component, capabilities.mode.supportedModes(supportedTemperatureLevels))
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
  -- TODO: Create laundryWasherSpinSpeed
  -- device:emit_event_for_endpoint(ib.endpoint_id, capabilities.laundryWasherSpinSpeed.supportedSpinSpeeds(laundryWasherControlsSpinSpeeds))
  local component = device.profile.components["laundryWasherSpinSpeed"]
  device:emit_component_event(component, capabilities.mode.supportedModes(laundryWasherControlsSpinSpeeds))
end

local function laundry_washer_controls_spin_speed_current_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("laundry_washer_controls_spin_speed_current_attr_handler spinSpeedCurrent: %s", ib.data.value))

  local spinSpeedCurrent = ib.data.value
  for i, spinSpeed in ipairs(laundryWasherControlsSpinSpeeds) do
    if i - 1 == spinSpeedCurrent then
      -- TODO: Create laundryWasherSpinSpeed
      -- device:emit_event_for_endpoint(ib.endpoint_id, capabilities.laundryWasherSpinSpeed.spinSpeed(spinSpeed))
      local component = device.profile.components["laundryWasherSpinSpeed"]
      device:emit_component_event(component, capabilities.mode.mode(spinSpeed))
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
    log.info_with({ hub_logs = true }, string.format("numberOfRinses: %s => %s", numberOfRinses.value, LAUNDRY_WASHER_RINSE_MODE_MAP[numberOfRinses.value]))
    table.insert(laundryWasherControlsSupportedRinses, LAUNDRY_WASHER_RINSE_MODE_MAP[numberOfRinses.value])
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.laundryWasherRinseMode.supportedRinseModes(laundryWasherControlsSupportedRinses))
end

local function operational_state_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("operational_state_attr_handler operationalState: %s", ib.data.value))

  if ib.data.value == clusters.OperationalState.types.OperationalStateEnum.STOPPED then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperationalState.operatingState.stopped())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.RUNNING then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperationalState.operatingState.running())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.PAUSED then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperationalState.operatingState.paused())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.ERROR then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperationalState.operatingState.error())
  end
end

local function operational_error_attr_handler(driver, device, ib, response)
  -- TODO: Add error enum to dishwasherOperatingState
  log.info_with({ hub_logs = true },
    string.format("operational_error_attr_handler errorStateID: %s", ib.data.elements.error_state_id.value))

  local operationalError = ib.data.elements.error_state_id.value
  if operationalError == clusters.OperationalState.types.ErrorStateEnum.NO_ERROR then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperationalState.operatingError.noError())
  elseif operationalError == clusters.OperationalState.types.ErrorStateEnum.UNABLE_TO_START_OR_RESUME then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperationalState.operatingError.unableToStartOrResume())
  elseif operationalError == clusters.OperationalState.types.ErrorStateEnum.UNABLE_TO_COMPLETE_OPERATION then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperationalState.operatingError.unableToCompleteOperation())
  elseif operationalError == clusters.OperationalState.types.ErrorStateEnum.COMMAND_INVALID_IN_STATE then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperationalState.operatingError.commandInvalidInState())
  end
end

-- Capability Handlers --
local function handle_laundry_washer_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("handle_laundry_washer_mode[%s] mode: %s", cmd.component, cmd.args.mode))

  local ENDPOINT = 1
  -- TODO: Create laundryWasherSpinSpeed
  -- for i, mode in ipairs(laundryWasherModeSupportedModes) do
  --   if cmd.args.mode == mode then
  --     device:send(clusters.LaundryWasherMode.commands.ChangeToMode(device, ENDPOINT, i - 1))
  --     return
  --   end
  -- end
  if cmd.component == "main" then
    for i, mode in ipairs(laundryWasherModeSupportedModes) do
      if cmd.args.mode == mode then
        device:send(clusters.LaundryWasherMode.commands.ChangeToMode(device, ENDPOINT, i - 1))
        return
      end
    end
  elseif cmd.component == "laundryWasherSpinSpeed" then
    for i, spinSpeed in ipairs(laundryWasherControlsSpinSpeeds) do
      if cmd.args.mode == spinSpeed then
        device:send(clusters.LaundryWasherControls.attributes.SpinSpeedCurrent:write(device, ENDPOINT, i - 1))
        return
      end
    end
  elseif cmd.component == "temperatureLevel" then
    -- TODO Create temperatureLevel
    for i, tempLevel in ipairs(supportedTemperatureLevels) do
      if cmd.args.mode == tempLevel then
        device:send(clusters.TemperatureControl.commands.SetTemperature(device, ENDPOINT, nil, i - 1))
        return
      end
    end
  end
end

-- TODO: Create laundryWasherSpinSpeed
-- local function handle_laundry_washer_spin_speed(driver, device, cmd)
--   log.info_with({ hub_logs = true },
--     string.format("handle_laundry_washer_spin_speed spinSpeed: %s", cmd.args.spinSpeed))

--   local ENDPOINT = 1
--   for i, spinSpeed in ipairs(laundryWasherControlsSpinSpeeds) do
--     if cmd.args.spinSpeed == spinSpeed then
--       device:send(clusters.LaundryWasherControls.attributes.SpinSpeedCurrent:write(device, ENDPOINT, i - 1))
--       return
--     end
--   end
-- end

local function handle_laundry_washer_rinse_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("handle_laundry_washer_rinse_mode rinseMode: %s", cmd.args.rinseMode))

  local ENDPOINT = 1
  for clusterVal, capabilityVal in pairs(LAUNDRY_WASHER_RINSE_MODE_MAP) do
    if cmd.args.rinseMode == capabilityVal then
      device:send(clusters.LaundryWasherControls.attributes.NumberOfRinses:write(device, ENDPOINT, clusterVal))
      break
    end
  end
end

local function handle_set_operating_state(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("handle_set_operating_state state: %s", cmd.args.state))

  local endpoint_id = device:component_to_endpoint(cmd.component)
  local state = cmd.args.state
  local latest_state = device:get_latest_state(
    cmd.component, applianceOperationalStateId,
    applianceOperationalState.operatingState.NAME
  )
  if state == applianceOperationalState.operatingState.stopped.NAME then
    device:send(clusters.OperationalState.server.commands.Stop(device, endpoint_id))
  elseif state == applianceOperationalState.operatingState.running.NAME then
    if latest_state == applianceOperationalState.operatingState.paused.NAME then
      device:send(clusters.OperationalState.server.commands.Resume(device, endpoint_id))
    else
      device:send(clusters.OperationalState.server.commands.Start(device, endpoint_id))
    end
  elseif state == applianceOperationalState.operatingState.paused.NAME then
    device:send(clusters.OperationalState.server.commands.Pause(device, endpoint_id))
  end
  -- If this attribute is not read, the capability will not be updated and the app will receive a network error.
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
        [clusters.OperationalState.attributes.OperationalState.ID] = operational_state_attr_handler,
        [clusters.OperationalState.attributes.OperationalError.ID] = operational_error_attr_handler,
      },
    }
  },
  capability_handlers = {
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_laundry_washer_mode,
      -- TODO: Create laundryWasherSpinSpeed
      -- [capabilities.laundryWasherSpinSpeed.commands.setSpinSpeed.NAME] = handle_laundry_washer_spin_speed,
      [capabilities.laundryWasherRinseMode.commands.setRinseMode.NAME] = handle_laundry_washer_rinse_mode,
    },
    [applianceOperationalStateId] = {
      [applianceOperationalState.commands.setOperatingState.NAME] = handle_set_operating_state,
    },
  },
  can_handle = is_matter_laundry_washer,
}

return matter_laundry_washer_handler
