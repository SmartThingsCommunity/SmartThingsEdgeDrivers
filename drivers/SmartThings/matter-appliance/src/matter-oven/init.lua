-- Copyright 2024 SmartThings
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
local log = require "log"
local version = require "version"
local embedded_cluster_utils = require "embedded-cluster-utils"
local utils = require "st.utils"

if version.api < 10 then
  clusters.TemperatureControl = require "TemperatureControl"
end

--this cluster is not supported in any releases of the lua libs
clusters.OvenMode = require "OvenMode"

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
local SUPPORTED_OVEN_MODES_MAP = "__supported_oven_modes_map_key_"

local OVEN_DEVICE_ID = 0x007B
local COOK_SURFACE_DEVICE_TYPE_ID = 0x0077
local COOK_TOP_DEVICE_TYPE_ID = 0x0078
local TCC_DEVICE_TYPE_ID = 0x0071

-- This is a work around to handle when units for temperatureSetpoint is changed for the App.
-- When units are switched, we will never know the recevied command value is for what unit as the arguments don't contain the unit.
-- So to handle this we assume the following ranges considering usual oven temperatures:
--   1. if the recieved setpoint command value is in range 127 ~ 260, it is inferred as *C
--   2. if the received setpoint command value is in range 261 ~ 500, it is inferred as *F
local OVEN_MAX_TEMP_IN_C = 260
local OVEN_MIN_TEMP_IN_C = 127

local setpoint_limit_device_field = {
  MIN_TEMP = "MIN_TEMP",
  MAX_TEMP = "MAX_TEMP",
}

local function get_endpoints_for_dt(device, device_type)
  local endpoints = {}
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == device_type then
        table.insert(endpoints, ep.endpoint_id)
        break
      end
    end
  end
  table.sort(endpoints)
  return endpoints
end

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

local function is_oven_device(opts, driver, device)
  local oven_eps = get_endpoints_for_dt(device, OVEN_DEVICE_ID)
  if #oven_eps > 0 then
    return true
  end
  return false
end

-- Lifecycle Handlers --
local function device_init(driver, device)
  device:subscribe()
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local function device_added(driver, device)
  -- We assume the following endpoint structure of oven device for now
  local cook_surface_endpoints = get_endpoints_for_dt(device, COOK_SURFACE_DEVICE_TYPE_ID)
  local cook_top_endpoint = get_endpoints_for_dt(device, COOK_TOP_DEVICE_TYPE_ID)[1] or device.MATTER_DEFAULT_ENDPOINT
  local tcc_endpoints = get_endpoints_for_dt(device, TCC_DEVICE_TYPE_ID)
  local componentToEndpointMap = {
    ["tccOne"] = tcc_endpoints[1],
    ["tccTwo"] = tcc_endpoints[2],
    ["cookTop"] = cook_top_endpoint,
    ["cookSurfaceOne"] = cook_surface_endpoints[1],
    ["cookSurfaceTwo"] = cook_surface_endpoints[2]
  }
  device:set_field(COMPONENT_TO_ENDPOINT_MAP, componentToEndpointMap, { persist = true })
end

-- Matter Handlers --
local function oven_supported_modes_attr_handler(driver, device, ib, response)
  local supportedOvenModesMap = device:get_field(SUPPORTED_OVEN_MODES_MAP) or {}
  local supportedOvenModes = {}
  for _, mode in ipairs(ib.data.elements) do
    clusters.OvenMode.types.ModeOptionStruct:augment_type(mode)
    local modeLabel = mode.elements.label.value
    log.info("Inserting supported oven mode: "..modeLabel)
    table.insert(supportedOvenModes, modeLabel)
  end
  supportedOvenModesMap[string.format(ib.endpoint_id)] = supportedOvenModes
  device:set_field(SUPPORTED_OVEN_MODES_MAP, supportedOvenModesMap, {persist = true})
  local event = capabilities.mode.supportedModes(supportedOvenModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
  local event = capabilities.mode.supportedArguments(supportedOvenModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function oven_mode_attr_handler(driver, device, ib, response)
  log.info(string.format("oven_mode_attr_handler currentMode: %s", ib.data.value))

  local supportedOvenModesMap = device:get_field(SUPPORTED_OVEN_MODES_MAP) or {}
  local supportedOvenModes = supportedOvenModesMap[string.format(ib.endpoint_id)] or {}
  local currentMode = ib.data.value
  if supportedOvenModes[currentMode+1] then
    local mode = supportedOvenModes[currentMode+1]
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.mode(mode))
    return
  end
  log.warn("oven_mode_attr_handler received unsupported mode for endpoint"..ib.endpoint_id)
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
  local min = device:get_field(min_field) or OVEN_MIN_TEMP_IN_C
  local max = device:get_field(max_field) or OVEN_MAX_TEMP_IN_C
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
      capabilities.temperatureSetpoint.temperatureSetpointRange({value = range, unit = unit},{visibility = {displayed = false}}))
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

    val = utils.clamp_value(val, OVEN_MIN_TEMP_IN_C, OVEN_MAX_TEMP_IN_C)

    device.log.info("Setting " .. field .. " to " .. string.format("%s", val))
    device:set_field(field, val, { persist = true })
  end
end

-- Capability Handlers --
local function handle_oven_mode(driver, device, cmd)
  log.info(string.format("handle_oven_mode mode: %s", cmd.args.mode))
  local ep = component_to_endpoint(device, cmd.component)
  local supportedOvenModesMap = device:get_field(SUPPORTED_OVEN_MODES_MAP) or {}
  local supportedOvenModes = supportedOvenModesMap[string.format(ep)] or {}
  for i, mode in ipairs(supportedOvenModes) do
    if cmd.args.mode == mode then
      device:send(clusters.OvenMode.commands.ChangeToMode(device, ep, i - 1))
      return
    end
  end
  log.warn("handle_oven_mode received unsupported mode: ".." for endpoint: "..ep)
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
  local min = device:get_field(min_field) or OVEN_MIN_TEMP_IN_C
  local max = device:get_field(max_field) or OVEN_MAX_TEMP_IN_C

  if value > OVEN_MAX_TEMP_IN_C then
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

  local ep = component_to_endpoint(device, cmd.component)
  device:send(clusters.TemperatureControl.commands.SetTemperature(device, ep, utils.round(value * 100), nil))
end

local matter_oven_handler = {
  NAME = "matter-oven",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
  },
  matter_handlers = {
    attr = {
      [clusters.TemperatureControl.ID] = {
        [clusters.TemperatureControl.attributes.TemperatureSetpoint.ID] = temperature_setpoint_attr_handler,
        [clusters.TemperatureControl.attributes.MinTemperature.ID] = setpoint_limit_handler(
          setpoint_limit_device_field.MIN_TEMP),
        [clusters.TemperatureControl.attributes.MaxTemperature.ID] = setpoint_limit_handler(
          setpoint_limit_device_field.MAX_TEMP),
      },
      [clusters.OvenMode.ID] = {
        [clusters.OvenMode.attributes.SupportedModes.ID] = oven_supported_modes_attr_handler,
        [clusters.OvenMode.attributes.CurrentMode.ID] = oven_mode_attr_handler,
      },
    },
  },
  capability_handlers = {
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_oven_mode,
    },
    [capabilities.temperatureSetpoint.ID] = {
      [capabilities.temperatureSetpoint.commands.setTemperatureSetpoint.NAME] = handle_temperature_setpoint,
    }
  },
  can_handle = is_oven_device,
}

return matter_oven_handler
