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

local applianceOperatingStateId = "spacewonder52282.applianceOperatingState"
local applianceOperatingState = capabilities[applianceOperatingStateId]
local supportedTemperatureLevels = {}
local dishwasherModeSupportedModes = {}

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

local function operational_state_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("operational_state_attr_handler operationalState: %s", ib.data.value))

  if ib.data.value == clusters.OperationalState.types.OperationalStateEnum.STOPPED then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperatingState.operatingState.stopped())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.RUNNING then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperatingState.operatingState.running())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.PAUSED then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperatingState.operatingState.paused())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.ERROR then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperatingState.operatingState.error())
  end
end

local function operational_error_attr_handler(driver, device, ib, response)
  -- TODO: Add error enum to dishwasherOperatingState
  log.info_with({ hub_logs = true },
    string.format("operational_error_attr_handler errorStateID: %s", ib.data.elements.error_state_id.value))

  local operationalError = ib.data.elements.error_state_id.value
  if operationalError == clusters.OperationalState.types.ErrorStateEnum.NO_ERROR then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperatingState.operatingError.noError())
  elseif operationalError == clusters.OperationalState.types.ErrorStateEnum.UNABLE_TO_START_OR_RESUME then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperatingState.operatingError.unableToStartOrResume())
  elseif operationalError == clusters.OperationalState.types.ErrorStateEnum.UNABLE_TO_COMPLETE_OPERATION then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperatingState.operatingError.unableToCompleteOperation())
  elseif operationalError == clusters.OperationalState.types.ErrorStateEnum.COMMAND_INVALID_IN_STATE then
    device:emit_event_for_endpoint(ib.endpoint_id, applianceOperatingState.operatingError.commandInvalidInState())
  end
end

-- Capability Handlers --
local function handle_dishwasher_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("handle_dishwasher_mode mode: %s", cmd.args.mode))

  local ENDPOINT = 1
  -- TODO: Create temperatureLevel
  -- for i, mode in ipairs(dishwasherModeSupportedModes) do
  --   if cmd.args.mode == mode then
  --     device:send(clusters.DishwasherMode.commands.ChangeToMode(device, ENDPOINT, i - 1))
  --     return
  --   end
  -- end
  if cmd.component == "main" then
    for i, mode in ipairs(dishwasherModeSupportedModes) do
      if cmd.args.mode == mode then
        device:send(clusters.DishwasherMode.commands.ChangeToMode(device, ENDPOINT, i - 1))
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
        [clusters.OperationalState.attributes.OperationalState.ID] = operational_state_attr_handler,
        [clusters.OperationalState.attributes.OperationalError.ID] = operational_error_attr_handler,
      },
    }
  },
  capability_handlers = {
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_dishwasher_mode,
    },
  },
  can_handle = is_matter_dishwasher,
}

return matter_dishwasher_handler
