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
if version.api < 10 then
  clusters.RefrigeratorAlarm = require "RefrigeratorAlarm"
  clusters.RefrigeratorAndTemperatureControlledCabinetMode = require "RefrigeratorAndTemperatureControlledCabinetMode"
  clusters.TemperatureControl = require "TemperatureControl"
end

local REFRIGERATOR_DEVICE_TYPE_ID = 0x0070
local TEMPERATURE_CONTROLLED_CABINET_DEVICE_TYPE_ID = 0x0071

local setpoint_limit_device_field = {
  MIN_TEMP = "MIN_TEMP",
  MAX_TEMP = "MAX_TEMP",
}

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
local SUPPORTED_TEMPERATURE_LEVEL = "__supported_temperature_levels"
local SUPPORTED_REFRIGERATOR_TCC_MODES_MAP = "__supported_refrigerator_tcc_modes_map"

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

  table.sort(cabinet_eps)

  if #cabinet_eps > 1 then
    local componentToEndpointMap = { -- This is just a guess for now
      ["refrigerator"] = cabinet_eps[1],
      ["freezer"] = cabinet_eps[2]
    }
    device:set_field(COMPONENT_TO_ENDPOINT_MAP, componentToEndpointMap, {persist = true})
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

local function temperature_setpoint_attr_handler(driver, device, ib, response)
  local tn_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER})
  if #tn_eps == 0 then
    device.log.warn_with({ hub_logs = true }, string.format("Device does not support TEMPERATURE_NUMBER feature"))
    return
  end
  device.log.info_with({ hub_logs = true },
    string.format("temperature_setpoint_attr_handler: %d", ib.data.value))

  local min_field = string.format("%s-%d", setpoint_limit_device_field.MIN_TEMP, ib.endpoint_id)
  local max_field = string.format("%s-%d", setpoint_limit_device_field.MAX_TEMP, ib.endpoint_id)
  local min = device:get_field(min_field) or 0
  local max = device:get_field(max_field) or 100
  local unit = "C"
  local range = {
    minimum = min,
    maximum = max,
  }
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureSetpoint.temperatureSetpointRange({value = range, unit = unit}))

  local temp = ib.data.value / 100.0
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureSetpoint.temperatureSetpoint({value = temp, unit = unit}))
end

local function setpoint_limit_handler(limit_field)
  return function(driver, device, ib, response)
    local tn_eps = embedded_cluster_utils.get_endpoints(device,clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER})
    if #tn_eps == 0 then
      device.log.warn_with({ hub_logs = true }, string.format("Device does not support TEMPERATURE_NUMBER feature"))
      return
    end
    local field = string.format("%s-%d", limit_field, ib.endpoint_id)
    local val = ib.data.value / 100.0
    log.info("Setting " .. field .. " to " .. string.format("%s", val))
    device:set_field(field, val, { persist = true })
  end
end

local function selected_temperature_level_attr_handler(driver, device, ib, response)
  local tl_eps = embedded_cluster_utils.get_endpoints(device,clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL})
  if #tl_eps == 0 then
    device.log.warn_with({ hub_logs = true }, string.format("Device does not support TEMPERATURE_LEVEL feature"))
    return
  end
  device.log.info_with({ hub_logs = true },
    string.format("selected_temperature_level_attr_handler: %s", ib.data.value))

  local temperatureLevel = ib.data.value
  local supportedTemperatureLevels = device:get_field(SUPPORTED_TEMPERATURE_LEVEL)
  for i, tempLevel in ipairs(supportedTemperatureLevels) do
    if i - 1 == temperatureLevel then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureLevel.temperatureLevel(tempLevel))
      break
    end
  end
end

local function supported_temperature_levels_attr_handler(driver, device, ib, response)
  local tl_eps = embedded_cluster_utils.get_endpoints(device,clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL})
  if #tl_eps == 0 then
    device.log.warn_with({ hub_logs = true }, string.format("Device does not support TEMPERATURE_LEVEL feature"))
    return
  end
  local supportedTemperatureLevels = {}
  for _, tempLevel in ipairs(ib.data.elements) do
    log.info_with({ hub_logs = true },
      string.format("supported_temperature_levels_attr_handler: %s", tempLevel.value))
    table.insert(supportedTemperatureLevels, tempLevel.value)
  end
  device:set_field(SUPPORTED_TEMPERATURE_LEVEL, supportedTemperatureLevels, { persist = true })
  local event = capabilities.temperatureLevel.supportedTemperatureLevels(supportedTemperatureLevels, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function refrigerator_tcc_supported_modes_attr_handler(driver, device, ib, response)
  local supportedRefrigeratorTccModesMap = device:get_field(SUPPORTED_REFRIGERATOR_TCC_MODES_MAP) or {}
  local supportedRefrigeratorTccModes = {}
  for _, mode in ipairs(ib.data.elements) do
    if version.api < 10 then
      clusters.RefrigeratorAndTemperatureControlledCabinetMode.types.ModeOptionStruct:augment_type(mode)
    end
    table.insert(supportedRefrigeratorTccModes, mode.elements.label.value)
  end
  supportedRefrigeratorTccModesMap[ib.endpoint_id] = supportedRefrigeratorTccModes
  device:set_field(SUPPORTED_REFRIGERATOR_TCC_MODES_MAP, supportedRefrigeratorTccModesMap, {persist = true})
  local event = capabilities.mode.supportedModes(supportedRefrigeratorTccModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function refrigerator_tcc_mode_attr_handler(driver, device, ib, response)
  device.log.info_with({ hub_logs = true },
    string.format("refrigerator_tcc_mode_attr_handler currentMode: %s", ib.data.value))

  local supportedRefrigeratorTccModesMap = device:get_field(SUPPORTED_REFRIGERATOR_TCC_MODES_MAP)
  local supportedRefrigeratorTccModes = supportedRefrigeratorTccModesMap[ib.endpoint_id] or {}
  local currentMode = ib.data.value
  for i, mode in ipairs(supportedRefrigeratorTccModes) do
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
  device.log.info_with({ hub_logs = true },
  string.format("temp_event_handler: %s", ib.data.value))

  local temp
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
  device.log.info_with({ hub_logs = true },
    string.format("handle_refrigerator_tcc_mode mode: %s", cmd.args.mode))

  local ep = component_to_endpoint(device, cmd.component)
  local supportedRefrigeratorTccModesMap = device:get_field(SUPPORTED_REFRIGERATOR_TCC_MODES_MAP)
  local supportedRefrigeratorTccModes = supportedRefrigeratorTccModesMap[ep] or {}
  for i, mode in ipairs(supportedRefrigeratorTccModes) do
    if cmd.args.mode == mode then
      device:send(clusters.RefrigeratorAndTemperatureControlledCabinetMode.commands.ChangeToMode(device, ep, i - 1))
      return
    end
  end
end

local function handle_temperature_setpoint(driver, device, cmd)
  local tn_eps = embedded_cluster_utils.get_endpoints(device,clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER})
  if #tn_eps == 0 then
    device.log.warn_with({ hub_logs = true }, string.format("Device does not support TEMPERATURE_NUMBER feature"))
    return
  end
  device.log.info_with({ hub_logs = true },
    string.format("handle_temperature_setpoint: %s", cmd.args.setpoint))

  local value = cmd.args.setpoint
  local _, temp_setpoint = device:get_latest_state(
    cmd.component, capabilities.temperatureSetpoint.ID,
    capabilities.temperatureSetpoint.temperatureSetpoint.NAME,
    0, { value = 0, unit = "C" }
  )
  local ep = component_to_endpoint(device, cmd.component)
  local min_field = string.format("%s-%d", setpoint_limit_device_field.MIN_TEMP, ep)
  local max_field = string.format("%s-%d", setpoint_limit_device_field.MAX_TEMP, ep)
  local min = device:get_field(min_field) or 0
  local max = device:get_field(max_field) or 100
  if value < min or value > max then
    log.warn(string.format(
      "Invalid setpoint (%s) outside the min (%s) and the max (%s)",
      value, min, max
    ))
    device:emit_event_for_endpoint(ep, capabilities.temperatureSetpoint.temperatureSetpoint(temp_setpoint))
    return
  end

  local ep = component_to_endpoint(device, cmd.component)
  device:send(clusters.TemperatureControl.commands.SetTemperature(device, ep, utils.round(value * 100), nil))
end

local function handle_temperature_level(driver, device, cmd)
  local ep = component_to_endpoint(device, cmd.component)
  device.log.info_with({ hub_logs = true },
    string.format("handle_temperature_level: %s(%d)", cmd.args.temperatureLevel, ep))

  local supportedTemperatureLevels = device:get_field(SUPPORTED_TEMPERATURE_LEVEL)
  for i, tempLevel in ipairs(supportedTemperatureLevels) do
    if cmd.args.temperatureLevel == tempLevel then
      device:send(clusters.TemperatureControl.commands.SetTemperature(device, ep, nil, i - 1))
      return
    end
  end
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
        [clusters.TemperatureControl.attributes.TemperatureSetpoint.ID] = temperature_setpoint_attr_handler,
        [clusters.TemperatureControl.attributes.MinTemperature.ID] = setpoint_limit_handler(setpoint_limit_device_field.MIN_TEMP),
        [clusters.TemperatureControl.attributes.MaxTemperature.ID] = setpoint_limit_handler(setpoint_limit_device_field.MAX_TEMP),
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
    [capabilities.temperatureLevel.ID] = {
      [capabilities.temperatureLevel.commands.setTemperatureLevel.NAME] = handle_temperature_level,
    },
  },
  can_handle = is_matter_refrigerator,
}

return matter_refrigerator_handler
