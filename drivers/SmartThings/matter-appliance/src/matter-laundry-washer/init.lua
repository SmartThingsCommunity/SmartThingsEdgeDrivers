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

local function laundry_washer_supported_modes_attr_handler(driver, device, ib, response)
  laundryWasherModeSupportedModes = {}
  for _, mode in ipairs(ib.data.elements) do
    table.insert(laundryWasherModeSupportedModes, mode.elements.label.value)
  end
  -- TODO: Wait for laundryWasherSpinSpeed creation
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
      -- TODO: Wait for laundryWasherSpinSpeed creation
      -- device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.mode(mode))
      local component = device.profile.components["main"]
      device:emit_component_event(component, capabilities.mode.mode(mode))
      break
    end
  end
end

local function laundry_washer_controls_spin_speeds_attr_handler(driver, device, ib, response)
  laundryWasherControlsSpinSpeeds = {}
  for _, spinSpeed in ipairs(ib.data.elements) do
    table.insert(laundryWasherControlsSpinSpeeds, spinSpeed)
  end
  -- TODO: Wait for laundryWasherSpinSpeed creation
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
      -- TODO: Wait for laundryWasherSpinSpeed creation
      -- device:emit_event_for_endpoint(ib.endpoint_id, capabilities.laundryWasherSpinSpeed.spinSpeed(spinSpeed))
      local component = device.profile.components["laundryWasherSpinSpeed"]
      device:emit_component_event(component, capabilities.mode.mode(spinSpeed))
      break
    end
  end
end

local function laundry_washer_controls_number_of_rinses_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("laundry_washer_controls_number_of_rinses_attr_handler numberOfRinses: %s", ib.data.value))

  local numberOfRinses = ib.data.value
  for clusterVal, capabilityVal in pairs(LAUNDRY_WASHER_RINSE_MODE_MAP) do
    if numberOfRinses == clusterVal then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.laundryWasherRinseMode.rinseMode(capabilityVal))
      break
    end
  end
end

local function laundry_washer_controls_supported_rinses_attr_handler(driver, device, ib, response)
  laundryWasherControlsSupportedRinses = {}
  for _, numberOfRinses in ipairs(ib.data.elements) do
    table.insert(laundryWasherControlsSupportedRinses, LAUNDRY_WASHER_RINSE_MODE_MAP[numberOfRinses]())
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.laundryWasherRinseMode.supportedRinseModes(laundryWasherControlsSupportedRinses))
end

local function operational_state_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
  string.format("operational_state_attr_handler operationalState: %s", ib.data.value))

  if ib.data.value == clusters.OperationalState.types.OperationalStateEnum.STOPPED then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.washerOperatingState.machineState.stop())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.RUNNING then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.washerOperatingState.machineState.run())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.PAUSED then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.washerOperatingState.machineState.pause())
  end
end

local function operational_error_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("operational_error_attr_handler errorStateID: %s", ib.data.elements.error_state_id.value))
  -- TODO: Add error enum to washerOperatingState
  -- local operationalError = ib.data.elements.error_state_id.value
  -- if operationalError == clusters.OperationalState.types.ErrorStateEnum.UNABLE_TO_START_OR_RESUME then
  --   device:emit_event_for_endpoint(ib.endpoint_id, capabilities.washerOperatingState.machineState.unableToStartOrResume())
  -- elseif operationalError == clusters.OperationalState.types.ErrorStateEnum.UNABLE_TO_COMPLETE_OPERATION then
  --   device:emit_event_for_endpoint(ib.endpoint_id, capabilities.washerOperatingState.machineState.unableToCompleteOperation())
  -- elseif operationalError == clusters.OperationalState.types.ErrorStateEnum.COMMAND_INVALID_IN_STATE then
  --   device:emit_event_for_endpoint(ib.endpoint_id, capabilities.washerOperatingState.machineState.commandInvalidInState())
  -- end
end

-- Capability Handlers --
local function handle_laundry_washer_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("handle_laundry_washer_mode mode: %s", cmd.args.mode))

  local ENDPOINT = 1
  -- TODO: Wait for laundryWasherSpinSpeed creation
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
  end
end

-- TODO: Wait for laundryWasherSpinSpeed creation
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

-- local function handle_laundry_washer_rinse_mode(driver, device, cmd)
--   log.info_with({ hub_logs = true },
--     string.format("handle_laundry_washer_rinse_mode rinseMode: %s", cmd.args.rinseMode))

--   local ENDPOINT = 1
--   for cluster_val, capability_val in pairs(LAUNDRY_WASHER_RINSE_MODE_MAP) do
--     if cmd.args.rinseMode == capability_val then
--       device:send(clusters.LaundryWasherControls.attributes.NumberOfRinses:write(device, ENDPOINT, cluster_val))
--       break
--     end
--   end
-- end

local matter_laundry_washer_handler = {
  NAME = "matter-laundry-washer",
  lifecycle_handlers = {
    init = device_init,
  },
  matter_handlers = {
    attr = {
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
      -- TODO: Wait for laundryWasherSpinSpeed creation
      -- [capabilities.laundryWasherSpinSpeed.commands.setSpinSpeed.NAME] = handle_laundry_washer_spin_speed,
      -- [capabilities.laundryWasherRinseMode.commands.setRinseMode.NAME] = handle_laundry_washer_rinse_mode,
    },
  },
  can_handle = is_matter_laundry_washer,
}

return matter_laundry_washer_handler
