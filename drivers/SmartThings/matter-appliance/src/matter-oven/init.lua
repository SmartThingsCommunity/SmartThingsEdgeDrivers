-- Copyright 2025 SmartThings
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
local common_utils = require "common-utils"
local log = require "log"
local version = require "version"

if version.api < 10 then
  clusters.TemperatureControl = require "TemperatureControl"
end

if version.api < 12 then
  clusters.OvenMode = require "OvenMode"
end

local SUPPORTED_OVEN_MODES_MAP = "__supported_oven_modes_map_key_"

local OVEN_DEVICE_ID = 0x007B
local COOK_SURFACE_DEVICE_TYPE_ID = 0x0077
local COOK_TOP_DEVICE_TYPE_ID = 0x0078
local TCC_DEVICE_TYPE_ID = 0x0071

local function is_oven_device(opts, driver, device)
  local oven_eps = common_utils.get_endpoints_for_dt(device, OVEN_DEVICE_ID)
  if #oven_eps > 0 then
    return true
  end
  return false
end

-- Lifecycle Handlers --
local function device_added(driver, device)
  -- We assume the following endpoint structure of oven device for now
  local cook_surface_endpoints = common_utils.get_endpoints_for_dt(device, COOK_SURFACE_DEVICE_TYPE_ID)
  local cook_top_endpoint = common_utils.get_endpoints_for_dt(device, COOK_TOP_DEVICE_TYPE_ID)[1] or device.MATTER_DEFAULT_ENDPOINT
  local tcc_endpoints = common_utils.get_endpoints_for_dt(device, TCC_DEVICE_TYPE_ID)
  local componentToEndpointMap = {
    ["tccOne"] = tcc_endpoints[1],
    ["tccTwo"] = tcc_endpoints[2],
    ["cookTop"] = cook_top_endpoint,
    ["cookSurfaceOne"] = cook_surface_endpoints[1],
    ["cookSurfaceTwo"] = cook_surface_endpoints[2]
  }
  device:set_field(common_utils.COMPONENT_TO_ENDPOINT_MAP, componentToEndpointMap, { persist = true })
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
  event = capabilities.mode.supportedArguments(supportedOvenModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function oven_mode_attr_handler(driver, device, ib, response)
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
  common_utils.temperature_setpoint_attr_handler(device, ib, "oven")
end

local function setpoint_limit_handler(limit_field)
  return function(driver, device, ib, response)
    common_utils.setpoint_limit_handler(device, ib, limit_field, "oven")
  end
end

-- Capability Handlers --
local function handle_oven_mode(driver, device, cmd)
  local ep = device:component_to_endpoint(cmd.component)
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
  common_utils.handle_temperature_setpoint(device, cmd, "oven")
end

local matter_oven_handler = {
  NAME = "matter-oven",
  lifecycle_handlers = {
    added = device_added
  },
  matter_handlers = {
    attr = {
      [clusters.TemperatureControl.ID] = {
        [clusters.TemperatureControl.attributes.TemperatureSetpoint.ID] = temperature_setpoint_attr_handler,
        [clusters.TemperatureControl.attributes.MinTemperature.ID] = setpoint_limit_handler(common_utils.setpoint_limit_device_field.MIN_TEMP),
        [clusters.TemperatureControl.attributes.MaxTemperature.ID] = setpoint_limit_handler(common_utils.setpoint_limit_device_field.MAX_TEMP)
      },
      [clusters.OvenMode.ID] = {
        [clusters.OvenMode.attributes.SupportedModes.ID] = oven_supported_modes_attr_handler,
        [clusters.OvenMode.attributes.CurrentMode.ID] = oven_mode_attr_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_oven_mode
    },
    [capabilities.temperatureSetpoint.ID] = {
      [capabilities.temperatureSetpoint.commands.setTemperatureSetpoint.NAME] = handle_temperature_setpoint
    }
  },
  can_handle = is_oven_device
}

return matter_oven_handler
