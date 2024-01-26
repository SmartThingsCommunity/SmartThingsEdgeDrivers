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

local REFRIGERATOR_DEVICE_TYPE_ID = 0x0070
local TEMPERATURE_CONTROLLED_CABINET_DEVICE_TYPE_ID = 0x0071

local endpointToComponentMap = {}
local endpointToComponentTLMap = {}
local supportedTemperatureLevelsMap = {}
local refrigeratorTccModeSupportedModesMap = {}

local function endpoint_to_component(device, ep)
  local map = endpointToComponentMap
  if map[ep] and device.profile.components[map[ep]] then
    return map[ep]
  end
  return "main"
end

local function component_to_endpoint(device, component_name)
  local map = endpointToComponentMap
  for ep, component in pairs(map) do
    if component == component_name then return ep end
  end
  map = endpointToComponentTLMap
  for ep, component in pairs(map) do
    if component == component_name then return ep end
  end
  return 1
end

local function device_init(driver, device)
  device:subscribe()
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local function device_added(driver, device)
  local cabinet_eps = {}
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == TEMPERATURE_CONTROLLED_CABINET_DEVICE_TYPE_ID then
        table.insert(cabinet_eps, ep.endpoint_id)
        break
      end
    end
  end
  if #cabinet_eps > 1 then
    endpointToComponentMap = { -- This is just a guess for now
      [cabinet_eps[1]] = "refrigerator",
      [cabinet_eps[2]] = "freezer"
    }
    endpointToComponentTLMap = { -- This is just a guess for now
      [cabinet_eps[1]] = "refrigeratorTemperatureLevel",
      [cabinet_eps[2]] = "freezerTemperatureLevel"
    }
  end
end

-- Matter Handlers --
local function is_matter_refrigerator(opts, driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == REFRIGERATOR_DEVICE_TYPE_ID then
        return true
      end
    end
  end
  return false
end

-- TODO Create temperatureLevel
local function selected_temperature_level_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("selected_temperature_level_attr_handler: %s", ib.data.value))

  local temperatureLevel = ib.data.value
  local supportedTemperatureLevels = supportedTemperatureLevelsMap[ib.endpoint_id]
  for i, tempLevel in ipairs(supportedTemperatureLevels) do
    if i - 1 == temperatureLevel then
      local component = device.profile.components[endpointToComponentTLMap[ib.endpoint_id]]
      device:emit_component_event(component, capabilities.mode.mode(tempLevel))
      break
    end
  end
end

-- TODO Create temperatureLevel
local function supported_temperature_levels_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("supported_temperature_levels_attr_handler: %s", ib.data.elements))

  local supportedTemperatureLevels = {}
  for _, tempLevel in ipairs(ib.data.elements) do
    table.insert(supportedTemperatureLevels, tempLevel.value)
  end
  supportedTemperatureLevelsMap[ib.endpoint_id] = supportedTemperatureLevels
  local component = device.profile.components[endpointToComponentTLMap[ib.endpoint_id]]
  device:emit_component_event(component, capabilities.mode.supportedModes(supportedTemperatureLevels))
end

local function refrigerator_tcc_supported_modes_attr_handler(driver, device, ib, response)
  local refrigeratorTccModeSupportedModes = {}
  for _, mode in ipairs(ib.data.elements) do
    table.insert(refrigeratorTccModeSupportedModes, mode.elements.label.value)
  end
  refrigeratorTccModeSupportedModesMap[ib.endpoint_id] = refrigeratorTccModeSupportedModes
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.supportedModes(refrigeratorTccModeSupportedModes))
end

local function refrigerator_tcc_mode_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("refrigerator_tcc_mode_attr_handler currentMode: %s", ib.data.value))

  local currentMode = ib.data.value
  local refrigeratorTccModeSupportedModes = refrigeratorTccModeSupportedModesMap[ib.endpoint_id]
  for i, mode in ipairs(refrigeratorTccModeSupportedModes) do
    if i - 1 == currentMode then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.mode(mode))
      break
    end
  end
end

local function refrigerator_alarm_attr_handler(driver, device, ib, response)
  if ib.data.value & clusters.RefrigeratorAlarm.types.AlarmMap.DOOR_OPEN > 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.contactSensor.contact.open())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.contactSensor.contact.closed())
  end
end

local function temp_event_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
  string.format("temp_event_handler: %s", ib.data.value))

  local temp = 0
  local unit = "C"
  if ib.data.value == nil then
    temp = 0
  else
    temp = ib.data.value / 100.0
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperature({value = temp, unit = unit}))
end

-- Capability Handlers --
local function handle_refrigerator_tcc_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("handle_refrigerator_tcc_mode mode: %s", cmd.args.mode))

    -- local ENDPOINT = 1
    -- for i, mode in ipairs(refrigeratorTccModeSupportedModes) do
    --   if cmd.args.mode == mode then
    --     device:send(clusters.RefrigeratorAndTemperatureControlledCabinetMode.commands.ChangeToMode(device, ENDPOINT, i - 1))
    --     return
    --   end
    -- end
    local ep = component_to_endpoint(device, cmd.component)
    if cmd.component == "main" or cmd.component == "refrigerator" or cmd.component == "freezer" then
      local refrigeratorTccModeSupportedModes = refrigeratorTccModeSupportedModesMap[ep]
      for i, mode in ipairs(refrigeratorTccModeSupportedModes) do
        if cmd.args.mode == mode then
          device:send(clusters.RefrigeratorAndTemperatureControlledCabinetMode.commands.ChangeToMode(device, ep, i - 1))
          return
        end
      end
    elseif cmd.component == "refrigeratorTemperatureLevel" or cmd.component == "freezerTemperatureLevel" then
      -- TODO Create temperatureLevel
      local supportedTemperatureLevels = supportedTemperatureLevelsMap[ep]
      for i, tempLevel in ipairs(supportedTemperatureLevels) do
        if cmd.args.mode == tempLevel then
          device:send(clusters.TemperatureControl.commands.SetTemperature(device, ep, nil, i - 1))
          return
        end
      end
    end
end

local function handle_temperature_setpoint(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("handle_temperature_setpoint: %s", cmd.args.setpoint))

  local ep = component_to_endpoint(device, cmd.component)
  device:send(clusters.TemperatureControl.commands.SetTemperature(device, ep, cmd.args.setpoint, nil))
end

local matter_refrigerator_handler = {
  NAME = "matter-refrigerator",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
  },
  matter_handlers = {
    attr = {
      [clusters.TemperatureControl.ID] = {
        [clusters.TemperatureControl.attributes.SelectedTemperatureLevel.ID] = selected_temperature_level_attr_handler,
        [clusters.TemperatureControl.attributes.SupportedTemperatureLevels.ID] = supported_temperature_levels_attr_handler,
      },
      [clusters.RefrigeratorAndTemperatureControlledCabinetMode.ID] = {
        [clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.SupportedModes.ID] = refrigerator_tcc_supported_modes_attr_handler,
        [clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.CurrentMode.ID] = refrigerator_tcc_mode_attr_handler,
      },
      [clusters.RefrigeratorAlarm.ID] = {
        [clusters.RefrigeratorAlarm.attributes.State.ID] = refrigerator_alarm_attr_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler,
      },
    }
  },
  capability_handlers = {
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_refrigerator_tcc_mode,
    },
    [capabilities.temperatureSetpoint.ID] = {
      [capabilities.temperatureSetpoint.commands.setTemperatureSetpoint.NAME] = handle_temperature_setpoint,
    },
  },
  can_handle = is_matter_refrigerator,
}

return matter_refrigerator_handler
