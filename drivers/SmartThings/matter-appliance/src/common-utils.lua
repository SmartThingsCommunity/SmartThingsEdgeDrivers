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
local embedded_cluster_utils = require "embedded-cluster-utils"
local im = require "st.matter.interaction_model"

local common_utils = {}

common_utils.COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
common_utils.SUPPORTED_TEMPERATURE_LEVELS_MAP = "__supported_temperature_levels_map"

common_utils.setpoint_limit_device_field = {
  MIN_TEMP = "MIN_TEMP",
  MAX_TEMP = "MAX_TEMP"
}

function common_utils.get_endpoints_for_dt(device, device_type)
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

function common_utils.query_setpoint_limits(device)
  local setpoint_limit_read = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  if device:get_field(common_utils.setpoint_limit_device_field.MIN_TEMP) == nil then
    setpoint_limit_read:merge(clusters.TemperatureControl.attributes.MinTemperature:read())
  end
  if device:get_field(common_utils.setpoint_limit_device_field.MAX_TEMP) == nil then
    setpoint_limit_read:merge(clusters.TemperatureControl.attributes.MaxTemperature:read())
  end
  if #setpoint_limit_read.info_blocks ~= 0 then
    device:send(setpoint_limit_read)
  end
end

function common_utils.supports_temperature_level_endpoint(device, endpoint)
  local feature = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL
  local tl_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = feature})
  if #tl_eps == 0 then
    device.log.warn_with({ hub_logs = true }, string.format("Device does not support TEMPERATURE_LEVEL feature"))
    return false
  end
  for _, eps in ipairs(tl_eps) do
    if eps == endpoint then
      return true
    end
  end
  device.log.warn_with({ hub_logs = true }, string.format("Endpoint(%d) does not support TEMPERATURE_LEVEL feature", endpoint))
  return false
end

function common_utils.supports_temperature_number_endpoint(device, endpoint)
  local feature = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER
  local tn_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = feature})
  if #tn_eps == 0 then
    device.log.warn_with({ hub_logs = true }, string.format("Device does not support TEMPERATURE_NUMBER feature"))
    return false
  end
  for _, eps in ipairs(tn_eps) do
    if eps == endpoint then
      return true
    end
  end
  device.log.warn_with({ hub_logs = true }, string.format("Endpoint(%d) does not support TEMPERATURE_NUMBER feature", endpoint))
  return false
end

return common_utils
