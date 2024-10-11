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
local embedded_cluster_utils = require "embedded-cluster-utils"

local log = require "log"

local version = require "version"
if version.api < 10 then
  clusters.TemperatureControl = require "TemperatureControl"
end

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
local COOK_SURFACE_DEVICE_TYPE_ID = 0x0077
local COOK_TOP_DEVICE_TYPE_ID = 0x0078
local OVEN_DEVICE_ID = 0x007B

local SUPPORTED_TEMPERATURE_LEVELS_MAP = "__supported_temperature_levels_map"

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

local function table_contains(tab, val)
  for _, tab_val in ipairs(tab) do
    if tab_val == val then
      return true
    end
  end
  return false
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

local function device_init(driver, device)
  device:subscribe()
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local function device_added(driver, device)
  local cook_surface_endpoints = get_endpoints_for_dt(device, COOK_SURFACE_DEVICE_TYPE_ID)
  local componentToEndpointMap = {
    ["cookSurfaceOne"] = cook_surface_endpoints[1],
    ["cookSurfaceTwo"] = cook_surface_endpoints[2]
  }
  device:set_field(COMPONENT_TO_ENDPOINT_MAP, componentToEndpointMap, { persist = true })
end

local function do_configure(driver, device)
  local cook_surface_endpoints = get_endpoints_for_dt(device, COOK_SURFACE_DEVICE_TYPE_ID)

  local tl_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID,
    { feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL })

  local profile_name
  if #cook_surface_endpoints > 0 then
    profile_name = "cook-surface-one"
    if table_contains(tl_eps, cook_surface_endpoints[1]) then
      profile_name = profile_name .. "-tl"
    end

    -- we only support up to two cook surfaces
    if #cook_surface_endpoints > 1 then
      profile_name = profile_name .. "-cook-surface-two"
      if table_contains(tl_eps, cook_surface_endpoints[2]) then
        profile_name = profile_name .. "-tl"
      end
    end
  end

  if profile_name then
    device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({ profile = profile_name })
  end
end

local function is_cook_top_device(opts, driver, device, ...)
  local cook_top_eps = get_endpoints_for_dt(device, COOK_TOP_DEVICE_TYPE_ID)
  local oven_eps = get_endpoints_for_dt(device, OVEN_DEVICE_ID)
  -- we want to skip lifecycle events in cases where the device is an oven with a composed cook-top device
  if (#oven_eps > 0) and opts.dispatcher_class == "DeviceLifecycleDispatcher" then
    return false
  end
  if #cook_top_eps > 0 then
    return true
  end
  return false
end

-- Matter Handlers --
local function selected_temperature_level_attr_handler(driver, device, ib, response)
  local tl_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID,
    { feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL })
  if #tl_eps == 0 then
    log.warn_with({hub_logs = true}, string.format("Device does not support TEMPERATURE_LEVEL feature"))
    return
  end
  log.info(string.format("selected_temperature_level_attr_handler: %s", ib.data.value))

  local temperatureLevel = ib.data.value
  local supportedTemperatureLevelsMap = device:get_field(SUPPORTED_TEMPERATURE_LEVELS_MAP) or {}
  local supportedTemperatureLevels = supportedTemperatureLevelsMap[ib.endpoint_id] or {}
  if supportedTemperatureLevels[temperatureLevel+1] then
    local tempLevel = supportedTemperatureLevels[temperatureLevel+1]
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureLevel.temperatureLevel(tempLevel))
  end
  log.warn("Received unsupported temperature level for endpoint "..(ib.endpoint_id))
end

local function supported_temperature_levels_attr_handler(driver, device, ib, response)
  local tl_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID,
    { feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL })
  if #tl_eps == 0 then
    log.warn_with({hub_logs = true}, string.format("Device does not support TEMPERATURE_LEVEL feature"))
    return
  end

  local supportedTemperatureLevelsMap = device:get_field(SUPPORTED_TEMPERATURE_LEVELS_MAP) or {}
  local supportedTemperatureLevels = {}
  for _, tempLevel in ipairs(ib.data.elements) do
    log.info(string.format("supported_temperature_levels_attr_handler: %s", tempLevel.value))
    table.insert(supportedTemperatureLevels, tempLevel.value)
  end
  supportedTemperatureLevelsMap[ib.endpoint_id] = supportedTemperatureLevels
  device:set_field(SUPPORTED_TEMPERATURE_LEVELS_MAP, supportedTemperatureLevelsMap, { persist = true })
  local event = capabilities.temperatureLevel.supportedTemperatureLevels(supportedTemperatureLevels,
    { visibility = { displayed = false } })
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function temp_event_handler(driver, device, ib, response)
  device.log.info(string.format("temp_event_handler: %s", ib.data.value))

  local temp
  local unit = "C"
  if ib.data.value == nil then
    temp = 0
  else
    temp = ib.data.value / 100.0
  end
  device:emit_event_for_endpoint(ib.endpoint_id,
    capabilities.temperatureMeasurement.temperature({ value = temp, unit = unit }))
end

local function handle_temperature_level(driver, device, cmd)
  log.info(string.format("handle_temperature_level: %s", cmd.args.temperatureLevel))

  local endpoint_id = device:component_to_endpoint(cmd.component)
  local supportedTemperatureLevelsMap = device:get_field(SUPPORTED_TEMPERATURE_LEVELS_MAP) or {}
  local supportedTemperatureLevels = supportedTemperatureLevelsMap[endpoint_id] or {}
  for i, tempLevel in ipairs(supportedTemperatureLevels) do
    if cmd.args.temperatureLevel == tempLevel then
      device:send(clusters.TemperatureControl.commands.SetTemperature(device, endpoint_id, nil, i - 1))
      return
    end
  end
end

local matter_cook_top_handler = {
  NAME = "matter-cook-top",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure
  },
  matter_handlers = {
    attr = {
      [clusters.TemperatureControl.ID] = {
        [clusters.TemperatureControl.attributes.SelectedTemperatureLevel.ID] =
            selected_temperature_level_attr_handler,
        [clusters.TemperatureControl.attributes.SupportedTemperatureLevels.ID] =
            supported_temperature_levels_attr_handler,
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler,
      },
    }
  },
  capability_handlers = {
    [capabilities.temperatureLevel.ID] = {
      [capabilities.temperatureLevel.commands.setTemperatureLevel.NAME] = handle_temperature_level,
    }
  },
  can_handle = is_cook_top_device,
}

return matter_cook_top_handler
